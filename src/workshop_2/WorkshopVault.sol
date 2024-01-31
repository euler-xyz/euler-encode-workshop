// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    event Borrow(address indexed caller, address indexed owner, uint256 assets);
    event Repay(address indexed caller, address indexed receiver, uint256 assets);

    error outstandingDebt();

    uint256 public totalBorrowed;
    uint256 internal _totalAssets;

    mapping(address account => uint256 assets) internal owed;

    IEVC internal immutable evc;
    bytes private snapshot;

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
    }

    // [ASSIGNMENT]: what is the purpose of this modifier?
    // [ANSWER]: The modifier checks if msg.sender is called from the EVC directly
    // if it's not the EVC address it uses the EVC onBehalfOf (msg.sender) to make calls into a target contract with the encoded data
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
    // [ANSWER]: It is not called if the controlled is disabled for the account at the time of the checks
    
    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // [ANSWER]: No. This is because it's not necessary for checking minting or deposits as they aren't for borrowing
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
    // [ANSWER]: No, because it doesn't check for borrowing permissions

    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // [ANSWER]: It needs to be added additional checks for borrowing authorizations
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
    // [ANSWER]: yes as it enables the controller vault to stop being the controller if all loans are repaid
    // It shouldn't be unconditional as a user might be able to withdraw his/her collateral before paying up the loan
    function disableController() external {
        address msgSender = _msgSender();
        if (_debtOf(msgSender) == 0) {
            evc.disableController(_msgSender());
        } else {
            revert outstandingDebt();
        }
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // [ANSWER]:  to check whether account is healthy, it's the EVC calling, checks are in progress and calculating collaterals
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        uint256 liabilityAssets = _debtOf(account);

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
        revert();
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // [ANSWER]: To check health of vault, status of the snapshot and risk parameters
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // [ANSWER]: By the use of a snapshot that is stored in the vault to help compare between the current ad initial states of the vault

        return IVault.checkVaultStatus.selector;
    }

        
    //Add snapshot for comparison between initial and current state of vault
    function vaultSnapshot() internal virtual returns (bytes memory) {
        (uint256 currentTotalBorrowed,) = _interestMade();
        return abi.encode(_convertToAssets(totalSupply(), false), currentTotalBorrowed);
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 shares) {
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
    function borrow(uint256 assets, address receiver) external callThroughEVC {
        address msgSender = _msgSenderForBorrow();

        vaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");
        receiver = getAccountOwner(receiver);
        _increaseOwed(msgSender, assets);

        //emit the borrow event
        emit Borrow(msgSender, receiver, assets);

        IERC20(asset()).transfer(receiver, assets);

        _totalAssets -= assets;

        requireAccountAndVaultStatusCheck(msgSender);
    }
    
    function repay(uint256 assets, address receiver) external {
        address msgSender = _msgSender();

        if (!isControllerEnabled(receiver, address(this))) {
            revert();
        }

        vaultSnapshot();

        require(assets != 0, "No available Assets");
        IERC20(asset()).transferFrom(msgSender, address(this), assets);

        _totalAssets += assets;
        _decreaseOwed(receiver, assets);
        //emit repay event
        emit Repay(msgSender, receiver, assets);

        requireAccountAndVaultStatusCheck(address(0));
    }
    
    function pullDebt(address from, uint256 assets) external returns (bool) {
        address msgSender = _msgSenderForBorrow();

        if (!isControllerEnabled(from, address(this))) {
            revert();
        }

        vaultSnapshot();

        require(assets != 0, "Amount is zero");
        require(msgSender != from, "Pull debt");

        _decreaseOwed(from, assets);
        _increaseOwed(msgSender, assets);

        emit Repay(msgSender, from, assets);
        emit Borrow(msgSender, msgSender, assets);

        requireAccountAndVaultStatusCheck(msgSender);

        return true;
    }

    function liquidate(address violator, address collateral) external {
        address msgSender = _msgSenderForBorrow();

        if (msgSender == violator) {
            revert();
        }

        if (isAccountStatusCheckDeferred(violator)) {
            revert();
        }

        if (!isControllerEnabled(violator, address(this))) {
            revert();
        }

        vaultSnapshot();

        uint256 violator_balance = balanceOf(violator);
        uint256 msgSender_balance = balanceOf(msgSender);

        _decreaseOwed(violator, violator_balance);
        _increaseOwed(msgSender, msgSender_balance);

        emit Repay(msgSender, violator, violator_balance);
        emit Borrow(msgSender, msgSender, msgSender_balance);

        if (collateral == address(this)) {

            if (!isCollateralEnabled(violator, collateral)) {
                revert();
            }

            IERC20(asset()).transfer(msgSender, violator_balance);

        } else {
            liquidateCollateralShares(collateral, violator, msgSender, violator_balance);

            forgiveAccountStatusCheck(violator);
        }

        requireAccountAndVaultStatusCheck(msgSender);
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 totalAssets = _totalAssets;
        uint256 ownAssets = balanceOf(owner);

        return _convertToShares(ownAssets, false) > totalAssets ? _convertToShares(totalAssets, false) : ownAssets;
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        uint256 totalAssets = totalAssets();
        uint256 ownerShares = balanceOf(owner);

        return _convertToAssets(ownerShares, false) > totalAssets ? _convertToShares(totalAssets, false) : ownerShares;
    }

    function liquidateCollateralShares(
        address vault,
        address liquidated,
        address liquidator,
        uint256 shares
    ) public {
        bytes memory result =
            evc.controlCollateral(vault, liquidated, 0, abi.encodeCall(IERC20.transfer, (liquidator, shares)));

        if (!(result.length == 0 || abi.decode(result, (bool)))) {
            revert();
        }
    }

    function forgiveAccountStatusCheck(address account) internal {
        evc.forgiveAccountStatusCheck(account);
    }

    function requireAccountAndVaultStatusCheck(address account) internal {
        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
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
            revert();
        }

        return sender;
    }

    function isControllerEnabled(address account, address vault) internal view returns (bool) {
        return evc.isControllerEnabled(account, vault);
    }

    function isAccountStatusCheckDeferred(address account) internal view returns (bool) {
        return evc.isAccountStatusCheckDeferred(account);
    }

    function isCollateralEnabled(address account, address vault) internal view returns (bool) {
        return evc.isCollateralEnabled(account, vault);
    }

    function getAccountOwner(address account) internal view returns (address owner_out) {
        try evc.getAccountOwner(account) returns (address _owner) {
            owner_out = _owner;
        } catch {
            owner_out = account;
        }
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _interestCalc();

        return roundUp
            ? assets.mulDivUp(totalSupply() + 1, totalAssets() + currentTotalBorrowed + 1)
            : assets.mulDivDown(totalSupply() + 1, totalAssets() + currentTotalBorrowed + 1);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _interestCalc();

        return roundUp
            ? shares.mulDivUp(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1)
            : shares.mulDivDown(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1);
    }

    // Adding debt functions to ensure any pending debts are checked
    function _debtOf(address account) internal view virtual returns (uint256) {
        return owed[account];
    }

    function _increaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) + assets;
        totalBorrowed += assets;
    }

    function _decreaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) - assets;
        totalBorrowed -= assets;
    }

    // Add interest functions
    // Considering there is no interest in the vault at the moment, the following functions help in the borrowing functionailty only
    function _interestMade() internal virtual returns (uint256, uint256) {
        return (totalBorrowed, 0);
    }

    function _interestCalc() internal view virtual returns (uint256, uint256, bool) {
        return (totalBorrowed, 0, false);
    }

    function _updateInterest() internal virtual {}
}