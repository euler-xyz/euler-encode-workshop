// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "solmate/utils/ReentrancyGuard.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    IEVC internal immutable evc;
    bytes private snapshot;
    uint256 public supplyCap;
    uint256 public borrowCap;
    uint256 public totalBorrowed;
    uint256 internal constant SECONDS_PER_YEAR = 365.2425 * 86400; // Gregorian calendar
    int96 internal constant MAX_ALLOWED_INTEREST_RATE = int96(int256(uint256(5 * 1e27) / SECONDS_PER_YEAR));
    int96 internal constant MIN_ALLOWED_INTEREST_RATE = 0;
    uint256 internal constant ONE = 1e27;
    uint256 internal interestAccumulator = ONE;
    uint256 internal interestRate = 5;
    uint256 internal lastInterestUpdate;
    mapping(address account => uint256 assets) internal owed;
    mapping(address account => uint256) internal userInterestAccumulator;

    event Borrow(address indexed caller, address indexed owner, uint256 assets);
    event Repay(address indexed caller, address indexed receiver, uint256 assets);

    error ControllerDisabled();
    error SupplyCapExceeded();
    error BorrowCapExceeded();
    error OutstandingDebt();
    error AccountUnhealthy();
    error SnapshotNotTaken();

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
        lastInterestUpdate = block.timestamp;
    }

    // [ASSIGNMENT]: what is the purpose of this modifier?
    modifier callThroughEVC() {
        if (msg.sender == address(evc)) {
            _;
        } else {
            bytes memory result = evc.call(address(this), msg.sender, 0, msg.data);

            assembly {
                return(add(32, result), mload(result))
            }
        }
    }

    // [ASSIGNMENT]: why the account status check might not be necessary in certain situations?
    // [ASSIGNMENT]: is the vault status check always necessary? why?
    modifier withChecks(address account) {
        _;

        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    // [ASSIGNMENT]: can this function be used to authenticate the account for the sake of the borrow-related
    // operations? why?
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    // IVault
    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller?
    function disableController() external {
        address msgSender = _msgSender();
        if (debtOf(msgSender) == 0) {
            evc.disableController(msgSender);
        } else {
            revert OutstandingDebt();
        }
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the account health

        uint256 liabilityAssets = debtOf(account);

        if (liabilityAssets == 0) return IVault.checkAccountStatus.selector;

        for (uint256 i = 0; i < collaterals.length; ++i) {
            if (collaterals[i] == address(this)) {
                uint256 collateral = _convertToAssets(balanceOf(account), false);
                uint256 maxLiability = (collateral * 9) / 10;

                if (liabilityAssets <= maxLiability) {
                    return IVault.checkAccountStatus.selector;
                }
            }
        }

        revert AccountUnhealthy();
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health
        // Circuit breaker EIP-7256
        doCheckVaultStatus(snapshot);
        delete snapshot;

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?

        return IVault.checkVaultStatus.selector;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 shares) {
        takeVaultSnapshot();
        return super.deposit(assets, receiver);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 assets) {
        takeVaultSnapshot();
        return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 shares) {
        takeVaultSnapshot();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 assets) {
        takeVaultSnapshot();
        return super.redeem(shares, receiver, owner);
    }

    function transfer(
        address to,
        uint256 value
    ) public virtual override (ERC20, IERC20) callThroughEVC withChecks(_msgSender()) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override (ERC20, IERC20) callThroughEVC withChecks(from) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    // IWorkshopVault
    function borrow(
        uint256 assets,
        address receiver
    ) external virtual callThroughEVC withChecks(_msgSenderForBorrow()) nonReentrant {
        address msgSender = _msgSenderForBorrow();

        takeVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        receiver = getAccountOwner(receiver);

        _increaseOwed(msgSender, assets);

        emit Borrow(msgSender, receiver, assets);

        ERC20(asset()).transfer(receiver, assets);

        requireAccountAndVaultStatusCheck(msgSender);
    }

    function repay(uint256 assets, address receiver) external callThroughEVC withChecks(address(0)) nonReentrant {
        address msgSender = _msgSender();

        // sanity check: the receiver must be under control of the EVC
        if (!isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }

        takeVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        ERC20(asset()).transferFrom(msgSender, address(this), assets);

        _decreaseOwed(receiver, assets);

        emit Repay(msgSender, receiver, assets);

        requireAccountAndVaultStatusCheck(address(0));
    }

    function pullDebt(
        address from,
        uint256 assets
    ) external callThroughEVC withChecks(_msgSenderForBorrow()) nonReentrant returns (bool) {
        address msgSender = _msgSenderForBorrow();

        // sanity check: the account from which the debt is pulled must be under control of the EVC
        if (!isControllerEnabled(from, address(this))) {
            revert ControllerDisabled();
        }

        takeVaultSnapshot();

        require(assets != 0, "ZERO_AMOUNT");
        require(msgSender != from, "SELF_DEBT_PULL");

        _decreaseOwed(from, assets);
        _increaseOwed(msgSender, assets);

        emit Repay(msgSender, from, assets);
        emit Borrow(msgSender, msgSender, assets);

        requireAccountAndVaultStatusCheck(msgSender);

        return true;
    }

    function liquidate(address violator, address collateral) external {}

    function _msgSenderForBorrow() internal view returns (address) {
        address sender = msg.sender;
        bool controllerEnabled;

        if (sender == address(evc)) {
            (sender, controllerEnabled) = evc.getCurrentOnBehalfOfAccount(address(this));
        } else {
            controllerEnabled = evc.isControllerEnabled(sender, address(this));
        }

        if (!controllerEnabled) {
            revert ControllerDisabled();
        }

        return sender;
    }

    function takeVaultSnapshot() internal {
        if (snapshot.length == 0) {
            snapshot = doTakeVaultSnapshot();
        }
    }

    function doTakeVaultSnapshot() public virtual returns (bytes memory) {
        (uint256 currentTotalBorrowed,) = _accrueInterest();

        return abi.encode(_convertToAssets(totalSupply(), false), currentTotalBorrowed);
    }

    function doCheckVaultStatus(bytes memory oldSnapshot) public virtual {
        // sanity check in case the snapshot hasn't been taken
        if (oldSnapshot.length == 0) revert SnapshotNotTaken();

        _updateInterest();

        // validate the vault state here:
        (uint256 initialSupply, uint256 initialBorrowed) = abi.decode(oldSnapshot, (uint256, uint256));
        uint256 finalSupply = _convertToAssets(totalSupply(), false);
        uint256 finalBorrowed = totalBorrowed;

        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert SupplyCapExceeded();
        }

        if (borrowCap != 0 && finalBorrowed > borrowCap && finalBorrowed > initialBorrowed) {
            revert BorrowCapExceeded();
        }
    }

    function _accrueInterest() internal virtual returns (uint256, uint256) {
        (uint256 currentTotalBorrowed, uint256 currentInterestAccumulator, bool shouldUpdate) =
            _accrueInterestCalculate();

        if (shouldUpdate) {
            totalBorrowed = currentTotalBorrowed;
            interestAccumulator = currentInterestAccumulator;
            lastInterestUpdate = block.timestamp;
        }

        return (currentTotalBorrowed, currentInterestAccumulator);
    }

    function _accrueInterestCalculate() internal view virtual returns (uint256, uint256, bool) {
        uint256 timeElapsed = block.timestamp - lastInterestUpdate;
        uint256 oldTotalBorrowed = totalBorrowed;
        uint256 oldInterestAccumulator = interestAccumulator;

        if (timeElapsed == 0) {
            return (oldTotalBorrowed, oldInterestAccumulator, false);
        }

        uint256 newInterestAccumulator = (
            FixedPointMathLib.rpow(uint256(int256(interestRate) + int256(ONE)), timeElapsed, ONE)
                * oldInterestAccumulator
        ) / ONE;

        uint256 newTotalBorrowed = (oldTotalBorrowed * newInterestAccumulator) / oldInterestAccumulator;

        return (newTotalBorrowed, newInterestAccumulator, true);
    }

    function setInterestRate(uint256 _interestRate) external {
        interestRate = _interestRate;
    }

    function computeInterestRate(address market, address asset, uint32 utilisation) internal returns (int96) {
        int96 rate = computeInterestRateImpl(market, asset, utilisation);

        if (rate > MAX_ALLOWED_INTEREST_RATE) {
            rate = MAX_ALLOWED_INTEREST_RATE;
        } else if (rate < MIN_ALLOWED_INTEREST_RATE) {
            rate = MIN_ALLOWED_INTEREST_RATE;
        }

        return rate;
    }

    function computeInterestRateImpl(address, address, uint32) internal virtual returns (int96) {
        return int96(int256(uint256((1e27 * interestRate) / 100) / (86400 * 365)));
    }

    function _updateInterest() internal virtual {
        uint256 borrowed = totalBorrowed;
        uint256 poolAssets = totalAssets() + borrowed;

        uint32 utilisation;
        if (poolAssets != 0) {
            utilisation = uint32((borrowed * type(uint32).max) / poolAssets);
        }

        interestRate = uint256(int256(computeInterestRate(address(this), address(ERC20(asset())), utilisation)));
    }

    function getAccountOwner(address account) internal view returns (address owner) {
        try evc.getAccountOwner(account) returns (address _owner) {
            owner = _owner;
        } catch {
            owner = account;
        }
    }

    function _increaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = debtOf(account) + assets;
        totalBorrowed += assets;
        userInterestAccumulator[account] = interestAccumulator;
    }

    function _decreaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = debtOf(account) - assets;
        totalBorrowed -= assets;
        userInterestAccumulator[account] = interestAccumulator;
    }

    function debtOf(address account) public view virtual returns (uint256) {
        uint256 debt = owed[account];

        if (debt == 0) return 0;

        (, uint256 currentInterestAccumulator,) = _accrueInterestCalculate();
        return (debt * currentInterestAccumulator) / userInterestAccumulator[account];
    }

    function requireAccountAndVaultStatusCheck(address account) internal {
        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    function isControllerEnabled(address account, address vault) internal view returns (bool) {
        return evc.isControllerEnabled(account, vault);
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 totAssets = totalAssets();
        uint256 ownerAssets = _convertToAssets(balanceOf(owner), false);

        return ownerAssets > totAssets ? totAssets : ownerAssets;
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        uint256 totAssets = totalAssets();
        uint256 ownerShares = balanceOf(owner);

        return _convertToAssets(ownerShares, false) > totAssets ? _convertToShares(totAssets, false) : ownerShares;
    }

    function _convertToShares(uint256 assets, bool rounding) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();
        return rounding
            ? assets.mulDivUp(totalSupply() + 1, totalAssets() + currentTotalBorrowed + 1)
            : assets.mulDivDown(totalSupply() + 1, totalAssets() + currentTotalBorrowed + 1);
    }

    function _convertToAssets(uint256 shares, bool rounding) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return rounding
            ? shares.mulDivUp(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1)
            : shares.mulDivDown(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1);
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, true);
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, true);
    }
}
