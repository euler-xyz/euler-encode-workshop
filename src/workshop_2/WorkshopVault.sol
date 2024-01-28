// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;
import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    IEVC internal immutable evc;

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
    }

    // [ASSIGNMENT]: what is the purpose of this modifier?
//The main purpose of the callThroughEVC modifier is to enforce that the caller of the function is the designated EVC.caller is not the EVC, the modifier may use the EVC callback functionality to perform additional checks or validation. This callback mechanism allows the vault to interact with the EVC
//the modifier is intended to handle checks in a way that they are postponed or deferred until later in the execution,
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
//The account status check might not be necessary in a certain situations because some global constraints, like supply and borrow caps, could be redundant to check for every account within a batch
//also certain checks, such as those related to borrow caps, may require an initial snapshot of the vault state, and it could be impractical or unnecessary to perform these checks on each account individually.

    // [ASSIGNMENT]: is the vault status check always necessary? why?
// vault status check is not always necessary immediately after each operation, as the checks can be deferred. Vaults implement the checkVaultStatus function, and after performing an operation, they call requireVaultStatusCheck on the EVC to schedule a deferred callback for future status checks. 
//allowing the vault to efficiently manage and schedule status checks based on the specific needs of its operations.
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
//Not alone this function can do,it needs to check the users position, if users is in already borrow position it shouldn't allow that to take, this function just for the EVC to take on behalfOfAccount.
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
//To allow safe borrow it must check for how much is collateral ratio, health factor. Also one account can take part in borrowing in one vault.
    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller?
//The disableController function allows the controller of a vault to be disabled.This can happen an account repaying its debt in full.Disabling the controller means removing its authority, and the safety concerns could include potential disruptions to ongoing operations, impacts on outstanding debts, or consequences for the overall functionality of the vault. 
    function disableController() external {
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
//The function could evaluate the borrower's account and collateral status before allowing a borrowing operation.
//If the borrower's debt exceeds an certain health factor limit relative to their collateral, the function will stop for further borrowing to maintain vaults health
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
//The checkVaultStatus function is typically used by the Euler V1 Controller (EVC) to assess the health and validity of a vault.
//Takes of a stored snapshot of the vault's initial state.If the snapshot is missing or corrupted, it could revert the transaction to avoid unreliable health assessments.

    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
//If the vault status check needs access to the initial state of the vault, the function could utilize a stored snapshot to evaluate, cross check of the vaults health.
        return IVault.checkVaultStatus.selector;
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
    function borrow(uint256 assets, address receiver) external {}
    function repay(uint256 assets, address receiver) external {}
    function pullDebt(address from, uint256 assets) external returns (bool) {}
    function liquidate(address violator, address collateral) external {}
}
