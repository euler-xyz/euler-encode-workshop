// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    using FixedPointMathLib for uint256;

    event Borrow(address indexed caller, address indexed owner, uint256 assets);
    event Repay(address indexed caller, address indexed receiver, uint256 assets);

    error ControllerDisabled();
    error SharesSeizureFailed();
    error NoLiquidationOpportunity();

    IEVC internal immutable evc;

    // Borrowing model variable
    bytes private snapshot;
    uint256 public totalBorrowed;
    uint256 internal _totalAssets;
    mapping(address account => uint256 assets) internal owed;

    // Interest rate model variables
    uint256 internal interestRate = 10; // 10% APY
    uint256 internal lastInterestUpdate = block.timestamp;
    uint256 internal constant ONE = 1e27;
    uint256 internal interestAccumulator = ONE;

    mapping(address account => uint256) internal userInterestAccumulator;

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
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
        require(_debtOf(_msgSender()) == 0);
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the account health

        return IVault.checkAccountStatus.selector;
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?

        return IVault.checkVaultStatus.selector;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 shares) {
        _totalAssets += assets;
        return super.deposit(assets, receiver);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 assets) {
        return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 shares) {
        _totalAssets -= assets;
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 assets) {
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

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        return super.maxWithdraw(owner);
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner) - owed[owner];
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return roundUp
            ? assets.mulDivUp(totalSupply() + 1, _totalAssets + currentTotalBorrowed + 1)
            : assets.mulDivDown(totalSupply() + 1, _totalAssets + currentTotalBorrowed + 1);
    }

    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();
        return roundUp
            ? shares.mulDivUp(_totalAssets + currentTotalBorrowed + 1, totalSupply() + 1)
            : shares.mulDivDown(_totalAssets + currentTotalBorrowed + 1, totalSupply() + 1);
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, true);
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, true);
    }

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

    function createVaultSnapshot() internal {
        if (snapshot.length == 0) {
            snapshot = doCreateVaultSnapshot();
        }
    }

    function doCreateVaultSnapshot() internal virtual returns (bytes memory) {
        (uint256 currentTotalBorrowed,) = _accrueInterest();

        return abi.encode(_convertToAssets(totalSupply(), false), currentTotalBorrowed);
    }

    function requireAccountAndVaultStatusCheck(address account) internal {
        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    function getAccountOwner(address account) internal view returns (address owner) {
        try evc.getAccountOwner(account) returns (address _owner) {
            owner = _owner;
        } catch {
            owner = account;
        }
    }

    function _increaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) + assets;
        totalBorrowed += assets;
        userInterestAccumulator[account] = interestAccumulator;
    }

    function _decreaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) - assets;
        totalBorrowed -= assets;
        userInterestAccumulator[account] = interestAccumulator;
    }

    function _debtOf(address account) internal view virtual returns (uint256) {
        uint256 debt = owed[account];

        if (debt == 0) return 0;

        (, uint256 currentInterestAccumulator, bool shouldUpdate) = _accrueInterestCalculate();
        if(!shouldUpdate){
            return debt;
        }
        return (debt * currentInterestAccumulator) / userInterestAccumulator[account];
    }

    function debtOf(address account) public view virtual returns (uint256) {
        return _debtOf(account);
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
            FixedPointMathLib.rpow(uint256(int256(computeInterestRate()) + int256(ONE)), timeElapsed, ONE)
                * oldInterestAccumulator
        ) / ONE;

        uint256 newTotalBorrowed = (oldTotalBorrowed * newInterestAccumulator) / oldInterestAccumulator;

        return (newTotalBorrowed, newInterestAccumulator, true);
    }

    function computeInterestRate() internal view virtual returns (int96) {
        return int96(int256(uint256((1e27 * interestRate) / 100) / (86400 * 365)));
    }

    function isControllerEnabled(address account, address vault) internal view returns (bool) {
        return evc.isControllerEnabled(account, vault);
    }

    // IWorkshopVault
    function borrow(uint256 assets, address receiver) external callThroughEVC {
        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        // users might input an EVC subaccount, in which case we want to send tokens to the owner
        receiver = getAccountOwner(receiver);

        _increaseOwed(msgSender, assets);

        emit Borrow(msgSender, receiver, assets);

        IERC20(asset()).transfer(receiver, assets);

        _totalAssets -= assets;

        requireAccountAndVaultStatusCheck(msgSender);
    }

    function repay(uint256 assets, address receiver) external callThroughEVC {
        address msgSender = _msgSender();

        if (!isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        IERC20(asset()).transferFrom(msgSender, address(this), assets);

        _totalAssets += assets;

        _decreaseOwed(receiver, assets);

        emit Repay(msgSender, receiver, assets);

        requireAccountAndVaultStatusCheck(address(0));
    }

    function pullDebt(address from, uint256 assets) external callThroughEVC returns (bool) {
        address msgSender = _msgSenderForBorrow();

        if (!isControllerEnabled(from, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        require(assets != 0, "ZERO_AMOUNT");
        require(msgSender != from, "SELF_DEBT_PULL");

        _decreaseOwed(from, assets);
        _increaseOwed(msgSender, assets);

        emit Repay(msgSender, from, assets);
        emit Borrow(msgSender, msgSender, assets);

        requireAccountAndVaultStatusCheck(msgSender);

        return true;
    }

    /// Extremely naive liquidation implementation
    function liquidate(address violator, address collateral) external callThroughEVC {
        address msgSender = _msgSenderForBorrow();
        if (balanceOf(violator) >= debtOf(violator) ) {
            revert NoLiquidationOpportunity();
        }

        doCreateVaultSnapshot();
        
        uint256 seizeShares = debtOf(violator) ;

        _decreaseOwed(violator, seizeShares);
        _increaseOwed(msgSender, seizeShares);

        emit Repay(msgSender, violator, seizeShares);
        emit Borrow(msgSender, msgSender, seizeShares);

        _transfer(violator, msgSender, seizeShares);

        emit Transfer(violator, msgSender, seizeShares);
    }
}
