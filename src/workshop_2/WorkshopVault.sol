// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IEVC internal immutable evc;

    event Borrow(address indexed caller, address indexed owner, uint256 assets);
    event Repay(address indexed caller, address indexed receiver, uint256 assets);

    uint256 internal constant SECONDS_PER_YEAR = 365.2425 * 86400; // Gregorian calendar
    int96 internal constant MAX_ALLOWED_INTEREST_RATE = int96(int256(uint256(5 * 1e27) / SECONDS_PER_YEAR)); // 500% APR
    int96 internal constant MIN_ALLOWED_INTEREST_RATE = 0;
    uint256 internal constant ONE = 1e27;

    error OutstandingDebt();
    error ControllerDisabled();
    error CollateralDisabled();
    error SelfLiquidation();
    error AccountUnhealthy();
    error SnapshotNotTaken();
    error SupplyCapExceeded();
    error BorrowCapExceeded();

    uint256 public supplyCap;
    mapping(ERC4626 vault => uint256) internal collateralFactor;

    bytes private snapshot;
    int96 internal interestRate;
    uint256 internal interestRate256;
    uint256 internal lastInterestUpdate;
    uint256 internal interestAccumulator;
    uint256 public borrowCap;
    uint256 public totalBorrowed;
    mapping(address account => uint256 assets) internal owed;
    mapping(address account => uint256) internal userInterestAccumulator;
    uint256 private locked = 1;

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
        lastInterestUpdate = block.timestamp;
        interestAccumulator = ONE;
        interestRate256 = 3; // 3% APY
    }

    modifier nonReentrant() virtual {
        require(locked == 1, "REENTRANCY");

        locked = 2;

        _;

        locked = 1;
    }

    // [ASSIGNMENT]: what is the purpose of this modifier?
    // The modifier checks if (msg.sender) is the EVC, if it's not the EVC address it uses the EVC onBehalfOf
    // (msg.sender) to make calls into a target contract with the encoded data
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
    // It is not called if there is no Controller enabled for the Account at the time of the checks,
    // AccountStatusCheck is used for ensuring borrowers remain solvent.
    // Therefore it's not necessary for checking minting or deposits, because those functions aren't related to
    // borrowing
    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // VaultStatusCheck is optional but if implemented as in our case, it's necessary to always be required by the Vault
    // after each operation affecting the Vault's state
    modifier withChecks(address account) {
        _;

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
        owed[account] = debtOf(account) + assets;
        totalBorrowed += assets;
        userInterestAccumulator[account] = interestAccumulator;
    }

    function _decreaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = debtOf(account) - assets;
        totalBorrowed -= assets;
        userInterestAccumulator[account] = interestAccumulator;
    }

    // [ASSIGNMENT]: can this function be used to authenticate the account for the sake of the borrow-related
    // operations? why?
    // No, this function doesnot retrieve the message sender in the context of the EVC for a borrow operation
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // We should implement _msgSenderForBorrow(), where the function reverts if the vault is not enabled as a controller
    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    function _msgSenderForBorrow() internal view returns (address) {
        address onBehalfOfAccount = msg.sender;
        bool controllerEnabled;

        if (msg.sender == address(evc)) {
            (onBehalfOfAccount, controllerEnabled) = evc.getCurrentOnBehalfOfAccount(address(this));
        } else {
            controllerEnabled = evc.isControllerEnabled(onBehalfOfAccount, address(this));
        }

        if (!controllerEnabled) {
            revert ControllerDisabled();
        }

        return onBehalfOfAccount;
    }

    function doTakeVaultSnapshot() public virtual override returns (bytes memory) {
        (uint256 currentTotalBorrowed,) = _accrueInterest();

        // make total supply and total borrows snapshot:
        return abi.encode(_convertToAssets(totalSupply(), Math.Rounding.Floor), currentTotalBorrowed);
    }

    function takeVaultSnapshot() internal {
        if (snapshot.length == 0) {
            snapshot = doTakeVaultSnapshot();
        }
    }

    // IVault
    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller?
    // This function is used to remove/disable a controller from the vault, and it can only be called by evc.
    // even though accountStatus checks pass, it's not safe to unconditionally disable because it might change the order
    // of controllers in storage
    function disableController() external override nonReentrant {
        address msgSender = _msgSender();
        if (debtOf(msgSender) == 0) {
            evc.disableController(msgSender);
        } else {
            revert OutstandingDebt();
        }
    }

    function debtOf(address account) public view virtual returns (uint256) {
        // Take into account the interest rate accrual.
        uint256 debt = owed[account];

        if (debt == 0) return 0;

        (, uint256 currentInterestAccumulator,) = _accrueInterestCalculate();
        return (debt * currentInterestAccumulator) / userInterestAccumulator[account];
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

        // uint256 newInterestAccumulator = (
        //     pow(uint256(int256(interestRate) + int256(ONE)), timeElapsed, ONE)
        //         * oldInterestAccumulator
        // ) / ONE;
        uint256 newInterestAccumulator = uint256(int256(interestRate) + int256(ONE)) * timeElapsed / 1 days;

        uint256 newTotalBorrowed = (oldTotalBorrowed * newInterestAccumulator) / oldInterestAccumulator;

        return (newTotalBorrowed, newInterestAccumulator, true);
    }

    // This function is overridden to take into account the fact that some of the assets may be borrowed.
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 totAssets = totalAssets();
        uint256 ownerAssets = _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        // return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        return ownerAssets > totAssets ? totAssets : ownerAssets;
    }

    // This function is overridden to take into account the fact that some of the assets may be borrowed.
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        uint256 totAssets = totalAssets();
        uint256 ownerShares = balanceOf(owner);
        //  return ownerShares;
        return _convertToAssets(ownerShares, Math.Rounding.Floor) > totAssets
            ? _convertToShares(totAssets, Math.Rounding.Floor)
            : ownerShares;
    }

    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();
        return
            assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + currentTotalBorrowed + 1, rounding);
    }

    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return
            shares.mulDiv(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 10 ** _decimalsOffset(), rounding); //
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // to check whether it's the EVC calling
    // to check whether checks are in progress
    // to check account health and for calculating the collateral and liability
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the account health
        uint256 liabilityAssets = debtOf(account);

        if (liabilityAssets == 0) return IVault.checkAccountStatus.selector;

        // let's say that it's only possible to borrow against
        // the same asset up to 90% of its value
        for (uint256 i = 0; i < collaterals.length; ++i) {
            if (collaterals[i] == address(this)) {
                uint256 collateral = _convertToAssets(balanceOf(account), Math.Rounding.Floor);
                uint256 maxLiability = (collateral * 9) / 10;

                if (liabilityAssets <= maxLiability) {
                    return IVault.checkAccountStatus.selector;
                }
            }
        }

        revert AccountUnhealthy();

        // return IVault.checkAccountStatus.selector;
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // to check whether it's the EVC calling
    // to check vault health
    // to check risk parameters or any other constraints set by the vault's
    // to check that the snapshot status is valid
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health
        doCheckVaultStatus(snapshot);
        delete snapshot;

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // Integrate snapshot functionality, and access the snapshot to compare it with the current vault state

        return IVault.checkVaultStatus.selector;
    }

    function doCheckVaultStatus(bytes memory oldSnapshot) public virtual override {
        // sanity check in case the snapshot hasn't been taken
        if (oldSnapshot.length == 0) revert SnapshotNotTaken();

        // use the vault status hook to update the interest rate (it should happen only once per transaction).
        // EVC.forgiveVaultStatus check should never be used for this vault, otherwise the interest rate will not be
        // updated.
        _updateInterest();

        // validate the vault state here:
        (uint256 initialSupply, uint256 initialBorrowed) = abi.decode(oldSnapshot, (uint256, uint256));
        uint256 finalSupply = _convertToAssets(totalSupply(), Math.Rounding.Floor);
        uint256 finalBorrowed = totalBorrowed;

        // the supply cap can be implemented like this:
        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert SupplyCapExceeded();
        }

        // or the borrow cap can be implemented like this:
        if (borrowCap != 0 && finalBorrowed > borrowCap && finalBorrowed > initialBorrowed) {
            revert BorrowCapExceeded();
        }
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) nonReentrant returns (uint256 shares) {
        address msgSender = _msgSender();

        takeVaultSnapshot();

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        IERC20(asset()).safeTransferFrom(msgSender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msgSender, receiver, assets, shares);

        // return super.deposit(assets, receiver);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) nonReentrant returns (uint256 assets) {
        address msgSender = _msgSender();

        takeVaultSnapshot();

        assets = previewMint(shares);

        IERC20(asset()).safeTransferFrom(msgSender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msgSender, receiver, assets, shares);

        // return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 shares) {
        takeVaultSnapshot();

        receiver = getAccountOwner(receiver);

        _burn(owner, shares);

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

        // SafeERC20.safeTransfer(ERC20(asset()), receiver, assets);
        ERC20(asset()).transfer(receiver, assets);
    }

    function repay(
        uint256 assets,
        address receiver
    ) external virtual callThroughEVC withChecks(address(0)) nonReentrant {
        address msgSender = _msgSender();

        if (!evc.isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }

        takeVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        // SafeERC20.safeTransferFrom(ERC20(asset()), msgSender, address(this), assets);
        ERC20(asset()).transferFrom(msgSender, address(this), assets);

        _decreaseOwed(receiver, assets);

        emit Repay(msgSender, receiver, assets);
    }

    function pullDebt(
        address from,
        uint256 assets
    ) external callThroughEVC withChecks(_msgSenderForBorrow()) nonReentrant returns (bool) {
        address msgSender = _msgSenderForBorrow();

        if (!evc.isControllerEnabled(from, address(this))) {
            revert ControllerDisabled();
        }

        takeVaultSnapshot();

        require(assets != 0, "ZERO_AMOUNT");
        require(msgSender != from, "SELF_DEBT_PULL");

        _decreaseOwed(from, assets);
        _increaseOwed(msgSender, assets);

        emit Repay(msgSender, from, assets);
        emit Borrow(msgSender, msgSender, assets);

        return true;
    }

    function liquidate(
        address violator,
        address collateral
    ) external virtual override callThroughEVC nonReentrant withChecks(_msgSenderForBorrow()) {
        address msgSender = _msgSenderForBorrow();

        if (msgSender == violator) {
            revert SelfLiquidation();
        }

        // sanity check: the violator must be under control of the EVC
        if (!evc.isControllerEnabled(violator, address(this))) {
            revert ControllerDisabled();
        }

        // do not allow to seize the assets for collateral without a collateral factor.
        uint256 cf = collateralFactor[ERC4626(collateral)];
        if (cf == 0) {
            revert CollateralDisabled();
        }

        takeVaultSnapshot();

        uint256 seizeShares = ERC4626(collateral).convertToShares(debtOf(violator));

        _decreaseOwed(violator, seizeShares);
        _increaseOwed(msgSender, seizeShares);

        emit Repay(msgSender, violator, seizeShares);
        emit Borrow(msgSender, msgSender, seizeShares);

        if (collateral == address(this)) {
            // if the liquidator tries to seize the assets from this vault,
            // we need to be sure that the violator has enabled this vault as collateral
            if (!evc.isCollateralEnabled(violator, collateral)) {
                revert CollateralDisabled();
            }

            ERC20(asset()).transferFrom(violator, msgSender, seizeShares);
        } else {
            evc.forgiveAccountStatusCheck(violator);
        }
    }

    function setInterestRate(uint256 _interestRate256) internal {
        interestRate256 = _interestRate256;
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
        return int96(int256(uint256((1e27 * interestRate256) / 100) / (86400 * 365))); // not SECONDS_PER_YEAR to avoid
            // breaking tests
    }

    function _updateInterest() internal virtual {
        uint256 borrowed = totalBorrowed;
        uint256 poolAssets = totalAssets() + borrowed;

        uint32 utilisation;
        if (poolAssets != 0) {
            utilisation = uint32((borrowed * type(uint32).max) / poolAssets);
        }

        interestRate = computeInterestRate(address(this), address(ERC20(asset())), utilisation);
    }

    function pow(uint256 base, uint256 exp, uint256 modulus) internal pure returns (uint256 result) {
        result = 1;
        base %= modulus;
        while (exp > 0) {
            if (exp & 1 == 1) {
                result = mulmod(result, base, modulus);
            }
            base = mulmod(base, base, modulus);
            exp >>= 1;
        }
    }
}
