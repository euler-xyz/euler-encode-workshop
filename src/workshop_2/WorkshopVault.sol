// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

import "solmate/utils/FixedPointMathLib.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    using FixedPointMathLib for uint256;
    IEVC internal immutable evc;
    bytes private snapshot;
    uint256 public totalBorrowed;
    uint256 public supplyCap;
    uint256 internal _totalAssets;    
    mapping(address account => uint256 assets) internal owed;
    event Borrow(address indexed caller, address indexed owner, uint256 assets);    
    event Repay(address indexed caller, address indexed receiver, uint256 assets);    
    error ControllerDisabled();
    error DisableControllerOutstandingDebt();
    error SnapshotNotTaken();
    error SupplyCapExceeded();

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
        supplyCap = 1e36;
    }

    // [ASSIGNMENT]: what is the purpose of this modifier?
    // This ensures that msg.sender is the EVC to use EVC functionality, imitate that the vault is always called by EVC, but we want still be ERC4626 compliant, so all functions (like the deposit function) can be called directly.
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
    // For example, when the user deposits more money, this does not negatively affect the solvency, so account status check is not necessary.
    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // when the transfer function is called, and shares are transfered between users, this doesn't affect total supply or total assets, so checks for vault health may not be necessary.
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
    // no, this should only possible if the controller is enabled
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // function _msgSenderForBorrow() is also defined below. There needs to be an additional check if controller is enabled, otherwise the borrow transactions should revert:
    //     function _msgSenderForBorrow() internal view returns (address) {
    //     address sender = msg.sender;
    //     bool controllerEnabled;

    //     if (sender == address(evc)) {
    //         (sender, controllerEnabled) = evc.getCurrentOnBehalfOfAccount(address(this));
    //     } else {
    //         controllerEnabled = evc.isControllerEnabled(sender, address(this));
    //     }

    //     if (!controllerEnabled) {
    //         revert ControllerDisabled();
    //     }

    //     return sender;
    // }
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
    // Disabling the controller should only be possible when all outstanding debt is repaid, otherwise a user can just borrow a lot of money and then withdraw the collateral if it is possible to unconditionally disable the controller, never having to pay back the debt and walk away.
    function disableController() external virtual override(IVault, IWorkshopVault){
        address msgSender = _msgSender();
        if (_debtOf(msgSender) > 0) {
            revert DisableControllerOutstandingDebt();
        }
        else{
            evc.disableController(_msgSender());
        }
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // check if the account is healthy, i.e. how much debt the user has compared to the collateral, and if there is a danger of liquidation.
    // Can be used when user wants to borrow more money to check if this should be allowed.
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual override(IVault, IWorkshopVault) returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the account health

        return IVault.checkAccountStatus.selector;
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // for example supply caps, borrow caps, interest rate caps 
    // for example when supply is exceeded with a deposit, then this can be used to revert the deposit transaction.
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        doCheckVaultStatus(snapshot);
        delete snapshot;

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // need to implement a snapshot and store that.

        return IVault.checkVaultStatus.selector;
    }

    /// @notice Checks the vault's status.
    /// @dev This function is called after any action that may affect the vault's state.
    /// @param oldSnapshot The snapshot of the vault's state before the action.
    function doCheckVaultStatus(bytes memory oldSnapshot) internal virtual  {
        // sanity check in case the snapshot hasn't been taken
        if (oldSnapshot.length == 0) revert SnapshotNotTaken();

        // validate the vault state here:
        uint256 initialSupply = abi.decode(oldSnapshot, (uint256));
        uint256 finalSupply = _convertToAssets(totalSupply(), false);

        // the supply cap can be implemented like this:
        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert SupplyCapExceeded();
        }
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 shares) {
        require(assets <= 1e36);
        createVaultSnapshot();
        shares = super.deposit(assets, receiver); 
        _totalAssets += assets;
        checkVaultStatus();
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 assets) {
        createVaultSnapshot();        
        assets =  super.mint(shares, receiver);
        _totalAssets += assets;
        checkVaultStatus();        
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 shares) {
        createVaultSnapshot();        
        shares = super.withdraw(assets, receiver, owner);
        _totalAssets -= assets;        
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 assets) {
        createVaultSnapshot();
        assets = super.redeem(shares, receiver, owner);
        _totalAssets -= assets;                
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

    /// @notice Creates a snapshot of the vault state
    function createVaultSnapshot() internal {
        // We delete snapshots on `checkVaultStatus`, which can only happen at the end of the EVC batch. Snapshots are
        // taken before any action is taken on the vault that affects the cault asset records and deleted at the end, so
        // that asset calculations are always based on the state before the current batch of actions.
        if (snapshot.length == 0) {
            snapshot = doCreateVaultSnapshot();
        }
    }

    /// @notice Creates a snapshot of the vault.
    /// @dev This function is called before any action that may affect the vault's state. Considering that and the fact
    /// that this function is only called once per the EVC checks deferred context, it can be also used to accrue
    /// interest.
    /// @return A snapshot of the vault's state.
    function doCreateVaultSnapshot() internal virtual returns (bytes memory) {
        (uint256 currentTotalBorrowed,) = _accrueInterest();

        // make total supply and total borrows snapshot:
        return abi.encode(_convertToAssets(totalSupply(), false), currentTotalBorrowed);
    }

    /// @notice Accrues interest.
    /// @dev Because this contract does not implement the interest accrual, this function does not need to update the
    /// state, but only returns the current value of total borrows and 0 for the interest accumulator. This function is
    /// needed so that it can be overriden by child contracts without a need to override other functions which use it.
    /// @return The current values of total borrowed and interest accumulator.
    function _accrueInterest() internal virtual returns (uint256, uint256) {
        return (totalBorrowed, 0);
    }

    /// @notice Retrieves the owner of an account.
    /// @dev Use with care. If the account is not registered on the EVC yet, the account address is returned as the
    /// owner.
    /// @param account The address of the account.
    /// @return owner The address of the account owner.
    function getAccountOwner(address account) internal view returns (address owner) {
        try evc.getAccountOwner(account) returns (address _owner) {
            owner = _owner;
        } catch {
            owner = account;
        }
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

    /// @notice Returns the debt of an account.
    /// @param account The account to check.
    /// @return The debt of the account.
    function _debtOf(address account) internal view virtual returns (uint256) {
        return owed[account];
    }

    /// @notice Returns the maximum amount that can be withdrawn by an owner.
    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    /// @param owner The owner of the assets.
    /// @return The maximum amount that can be withdrawn.
    function maxWithdraw(address owner) public view virtual override(ERC4626, IWorkshopVault) returns (uint256) {
        uint256 totAssets = totalAssets();
        uint256 ownerAssets = _convertToAssets(balanceOf(owner), false);

        return ownerAssets > totAssets ? totAssets : ownerAssets;
    }

    /// @notice Returns the maximum amount that can be redeemed by an owner.
    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    /// @param owner The owner of the assets.
    /// @return The maximum amount that can be redeemed.
    function maxRedeem(address owner) public view virtual override(ERC4626, IWorkshopVault) returns (uint256) {
        uint256 totAssets = totalAssets();
        uint256 ownerShares = balanceOf(owner);

        return _convertToAssets(ownerShares, false) > totAssets ? _convertToShares(totAssets, false) : ownerShares;
    }

    /// @notice Returns the total assets of the vault.
    /// @return The total assets.
    function totalAssets() public view virtual override returns (uint256) {
        return _totalAssets;
    }    


    /// @notice Retrieves the message sender in the context of the EVC for a borrow operation.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    /// either msg.sender or the account authenticated by the EVC. This function reverts if the vault is not enabled as
    /// a controller for the account on behalf of which the operation is being executed.
    /// @return The address of the message sender.
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


    /// @notice Checks whether a vault is enabled as a controller for an account.
    /// @param account The address of the account.
    /// @param vault The address of the vault.
    /// @return A boolean value that indicates whether the vault is an enabled controller for the account.
    function isControllerEnabled(address account, address vault) internal view returns (bool) {
        return evc.isControllerEnabled(account, vault);
    }

    /// @notice Converts shares to assets.
    /// @dev That function is manipulable in its current form as it uses exact values. Considering that other vaults may
    /// rely on it, for a production vault, a manipulation resistant mechanism should be implemented.
    /// @dev Considering that this function may be relied on by controller vaults, it's read-only re-entrancy protected.
    /// @param shares The shares to convert.
    /// @return The converted assets.
    function convertToAssets(uint256 shares) public view virtual override(ERC4626, IWorkshopVault) returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /// @notice Simulates the effects of depositing a certain amount of assets at the current block.
    /// @param assets The amount of assets to simulate depositing.
    /// @return The amount of shares that would be minted.
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, false);
    }

    /// @notice Simulates the effects of minting a certain amount of shares at the current block.
    /// @param shares The amount of shares to simulate minting.
    /// @return The amount of assets that would be deposited.
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, true);
    }

    /// @notice Simulates the effects of withdrawing a certain amount of assets at the current block.
    /// @param assets The amount of assets to simulate withdrawing.
    /// @return The amount of shares that would be burned.
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, true);
    }

    /// @notice Simulates the effects of redeeming a certain amount of shares at the current block.
    /// @param shares The amount of shares to simulate redeeming.
    /// @return The amount of assets that would be redeemed.
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /// @notice Converts assets to shares.
    /// @dev That function is manipulable in its current form as it uses exact values. Considering that other vaults may
    /// rely on it, for a production vault, a manipulation resistant mechanism should be implemented.
    /// @dev Considering that this function may be relied on by controller vaults, it's read-only re-entrancy protected.
    /// @param assets The assets to convert.
    /// @return The converted shares.
    function convertToShares(uint256 assets) public view virtual override(ERC4626, IWorkshopVault) returns (uint256) {
        return _convertToShares(assets, false);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

    return roundUp
        ? shares.mulDivUp(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1)
        : shares.mulDivDown(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1);
    }

    /// @dev This function is overridden to take into account the fact that some of the assets may be borrowed.
    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return roundUp
            ? assets.mulDivUp(totalSupply() + 1, totalAssets() + currentTotalBorrowed + 1)
            : assets.mulDivDown(totalSupply() + 1, totalAssets() + currentTotalBorrowed + 1);
    }    


    /// @notice Calculates the accrued interest.
    /// @dev Because this contract does not implement the interest accrual, this function does not need to calculate the
    /// interest, but only returns the current value of total borrows, 0 for the interest accumulator and false for the
    /// update flag. This function is needed so that it can be overriden by child contracts without a need to override
    /// other functions which use it.
    /// @return The total borrowed amount, the interest accumulator and a boolean value that indicates whether the data
    /// should be updated.
    function _accrueInterestCalculate() internal view virtual returns (uint256, uint256, bool) {
        return (totalBorrowed, 0, false);
    }


    // IWorkshopVault
    function borrow(uint256 assets, address receiver) external callThroughEVC withChecks(_msgSender()){
        address msgSender = _msgSenderForBorrow();
        createVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        // users might input an EVC subaccount, in which case we want to send tokens to the owner
        receiver = getAccountOwner(receiver);

        _increaseOwed(msgSender, assets);

        emit Borrow(msgSender, receiver, assets);

        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);
        _totalAssets -= assets;
    }
    function repay(uint256 assets, address receiver) external callThroughEVC withChecks(address(0)){
        address msgSender = _msgSender();

        // sanity check: the receiver must be under control of the EVC. otherwise, we allowed to disable this vault as
        // the controller for an account with debt
        if (!isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        SafeERC20.safeTransferFrom(IERC20(asset()), msgSender, address(this), assets);

        _totalAssets += assets;
        _decreaseOwed(receiver, assets);

        emit Repay(msgSender, receiver, assets);
    }
    function pullDebt(address from, uint256 assets) external callThroughEVC withChecks(_msgSender()) returns (bool) {
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
        return true;

    }
    // function liquidate(address violator, address collateral) external {

    // }
}
