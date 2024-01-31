// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault{

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    event Borrow(address indexed caller, address indexed owner, uint256 assets);
    event Repay(address indexed caller, address indexed receiver, uint256 assets);

    error OutstandingDebt();
    error ControllerDisabled();
    error CollateralDisabled();
    error SelfLiquidation();
    error AccountUnhealthy();
    error SnapshotNotTaken();
    error SupplyCapExceeded();
    error BorrowCapExceeded();

    IEVC internal immutable evc;
    uint256 internal constant ONE = 1e27;
    int96 internal interestRate = 6;
    uint256 internal lastInterestUpdate = block.timestamp;
    uint256 internal interestAccumulator = ONE;
    mapping(address account => uint256) internal userInterestAccumulator;
    mapping(ERC4626 vault => uint256) internal collateralFactor;
    mapping(address account => uint256 assets) internal owed;
    bytes private snapshot;
    uint256 locked;
    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
    }

    modifier nonReentrant() virtual {
        require(locked == 1, "REENTRANCY");

        locked = 2;

        _;

        locked = 1;
    }

    /// @notice Sets the collateral factor of a vault.
    /// @param vault The vault.
    /// @param _collateralFactor The new collateral factor.
    function setCollateralFactor(ERC4626 vault, uint256 _collateralFactor) external onlyOwner {
        if (_collateralFactor > COLLATERAL_FACTOR_SCALE) {
            revert InvalidCollateralFactor();
        }

        collateralFactor[vault] = _collateralFactor;
    }

    /// @notice Gets the collateral factor of a vault.
    /// @param vault The vault.
    /// @return The collateral factor.
    function getCollateralFactor(ERC4626 vault) external view returns (uint256) {
        return collateralFactor[vault];
    }

    /// @notice Gets the current interest rate of the vault.
    /// @return The current interest rate.
    function getInterestRate() external view returns (int256) {
        return int256(interestRate);
    }

    /// @notice Returns the debt of an account.
    /// @dev This function is overridden to take into account the interest rate accrual.
    /// @param account The account.
    /// @return The debt of the account.
    function debtOf(address account) public view virtual override returns (uint256) {
        uint256 debt = owed[account];

        if (debt == 0) return 0;

        (, uint256 currentInterestAccumulator,) = _accrueInterestCalculate();
        return (debt * currentInterestAccumulator) / userInterestAccumulator[account];
    }


    // [ASSIGNMENT]: what is the purpose of this modifier?
    // Answer: The purpose of this modifier is to route all the calls throught the EVC.
               // If EVC is the msg.sender the function execution continues, 
               // if not then a call to evc is made, which then calls back into this contract
               // "on behalf of" the msg.sender and executes the required functionality.

               // This is done so because EVC provides the optimal interface and a standardized approach to make account and vault related checks
               // and also help avoid unexpected reverts due to incorrect execution order of some functions.
               // Hence it is best to make the calls through the EVC, instead of directly 
    //  
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
    // Answer: The account status check might not be necessary in situations where 
            // the action performed does not affect the account's solvency.
            // It may also not be necessary if the account has not borrowed at all 😉

    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // Answer: It need not always be necessary for example during read-only actions
    //        However, The vault status check is necessary during state-modifying actions like borrowing,withdrawal, liquidation etc..
    //        and to enforce any vault-specific constraints like supply cap/borrow cap etc.
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

    //   Answer: No, this function cannot be used to authenticate the account for borrow-related actions.

    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?

    // Answer: This function should be modified in a way that it checks whether this vault is enabled as a controller for the account
    //         on behalf of which the borrow-realted actions are being executed. 
    //         It should also revert if the vault is not enabled as a controller for the account.
    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    function _msgSenderForBorrow() internal view virtual override returns (address) {
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

    /// @notice Returns the maximum amount that can be withdrawn by an owner.
    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    /// @param owner The owner of the assets.
    /// @return The maximum amount that can be withdrawn.
    function maxWithdraw(address owner) public view virtual override nonReentrantRO returns (uint256) {
        uint256 totAssets = _totalAssets;
        uint256 ownerAssets = _convertToAssets(balanceOf[owner], false);

        return ownerAssets > totAssets ? totAssets : ownerAssets;
    }

    /// @notice Returns the maximum amount that can be redeemed by an owner.
    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    /// @param owner The owner of the assets.
    /// @return The maximum amount that can be redeemed.
    function maxRedeem(address owner) public view virtual override nonReentrantRO returns (uint256) {
        uint256 totAssets = _totalAssets;
        uint256 ownerShares = balanceOf[owner];

        return _convertToAssets(ownerShares, false) > totAssets ? _convertToShares(totAssets, false) : ownerShares;
    }

    // IVault
    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller?

    // Answer : Since, the controller has full control of the account and can act on behalf of the user once the user borrows from the vault
    // a function like this becomes necessary so that the controller can be disabled once the user returns the borrowed amount for the safety of the user.
    //          
    // No, its not safe to unconditionally disable it, if done so the user could get away with the borrowed amount without returning it.
    // Hence, it becomes important to check the condition that the user does not have any liabilities
    // and has returned the borrowed amount before calling this function and disabling the controller
    // Its best to use this function only when required as improper use may lead to unexpected states/results.
    function disableController() external virtual override {
        // ensure that the account does not have any liabilities before disabling controller
        address msgSender = _msgSender();
        if (_debtOf(msgSender) == 0) {
            EVCClient.disableController(msgSender);
        } else {
            revert OutstandingDebt();
        }
    }

    // [ASSIGNMENT]: provide a couple use cases for this function

    // Answer: - It can be used to check the validity of the collaterals i.e checking if the collaterals are acceptable by the vault
    //        
    //         - It is used to enforce account solvency after any action that may affect an account's liquidity.
    //         - For example when an account makes an attempt to withdraw collateral, this function can be used 
    //         - to check whether the withdrawal would still keep the account solvent or not and take appropriate action
    //         - (such as returning some value if the account remains solvent or reverting if it gets insolvent etc..)
    //         - It can be used to check for any custom logic required.
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

    // Answer : - This function can be used to enforce any constraints that the vaults may have like 
    //             supply and/or borrow caps which restrict the maximum amount of assests that can be supplied/borrowed.

    //          - This can be also used to evaluate if the vault is in an acceptable state based on some application-specific logic.
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?

        // Answer: Before executing any action, each operation that needs to perform a vault status check 
        // should make an appropriate snapshot of the initial data and store it in transient storage
        // Then the operations can be executed and checkVaultStatus be invoked, it should evaluate the vault status 
        // by retrieving the snapshot data stored and compare it with the current vault status 
        // and return the success value or revert if something is violated
        return IVault.checkVaultStatus.selector;
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
    function borrow(uint256 assets, address receiver) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        // users might input an EVC subaccount, in which case we want to send tokens to the owner
        receiver = getAccountOwner(receiver);

        _increaseOwed(msgSender, assets);

        emit Borrow(msgSender, receiver, assets);

        asset.safeTransfer(receiver, assets);

        _totalAssets -= assets;

        requireAccountAndVaultStatusCheck(msgSender);
    }
    function repay(uint256 assets, address receiver) external callThroughEVC nonReentrant {
        address msgSender = _msgSender();

        // sanity check: the receiver must be under control of the EVC. otherwise, we allowed to disable this vault as
        // the controller for an account with debt
        if (!isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        asset.safeTransferFrom(msgSender, address(this), assets);

        _totalAssets += assets;

        _decreaseOwed(receiver, assets);

        emit Repay(msgSender, receiver, assets);

        requireAccountAndVaultStatusCheck(address(0));
    }
    function pullDebt(address from, uint256 assets) external callThroughEVC nonReentrant returns (bool) {
        address msgSender = _msgSenderForBorrow();

        // sanity check: the account from which the debt is pulled must be under control of the EVC.
        // _msgSenderForBorrow() checks that `msgSender` is controlled by this vault
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
    function liquidate(address violator, address collateral) external virtual override callThroughEVC nonReentrant withChecks(_msgSenderForBorrow()) {
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

    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    function _convertToShares(uint256 assets, bool roundUp) internal view virtual override returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return roundUp
            ? assets.mulDivUp(totalSupply + 1, _totalAssets + currentTotalBorrowed + 1)
            : assets.mulDivDown(totalSupply + 1, _totalAssets + currentTotalBorrowed + 1);
    }

    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual override returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return roundUp
            ? shares.mulDivUp(_totalAssets + currentTotalBorrowed + 1, totalSupply + 1)
            : shares.mulDivDown(_totalAssets + currentTotalBorrowed + 1, totalSupply + 1);
    }

    /// @notice Increases the owed amount of an account.
    /// @param account The account.
    /// @param assets The assets.
    function _increaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) + assets;
        totalBorrowed += assets;
    }

    /// @notice Decreases the owed amount of an account.
    /// @param account The account.
    /// @param assets The assets.
    function _decreaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) - assets;
        totalBorrowed -= assets;
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
}
}