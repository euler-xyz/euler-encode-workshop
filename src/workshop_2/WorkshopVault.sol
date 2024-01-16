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

// ------------------ DONE ------------------

    // [ASSIGNMENT]: what is the purpose of this modifier?
    
    // [ANSWER]
    // The purpose of the callThroughEVC modifier is to ensure that certain function calls are routed through
    // the EVC. 
    // If the caller is the EVC, then the function call is allowed to proceed. Otherwise, the function calls the EVC Interface
    // and that will call us back, making the EVC the caller in the excecution context.
    // This will take care of routing the calls through the EVC
    // and the vault we interact with can operate under the assumption that the checks are always
    // done correctly since the EVC acts as an authorizer, thus enhancing security.

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

 // ------------------ DONE------------------

    // [ASSIGNMENT]: why the account status check might not be necessary in certain situations?

    // [ANSWER]

    // Maybe the account wants to set up a private vault for itself and he is the only one who can access it.
    // and to excecute lending and borrowing operations only with certain accounts.
    // In this case, the account status can be conducted by the account itself and not by the EVC.

    // Also, there may be scenarios where the account status check is not
    // critical for the immediate health of the system.
    // For example, in situations where subsequent operations in the same tx will ensure
    // that the account status is valid by the end of the transaction.
    // Or the user could be borrowing with stablecoins as collateral the value of which is not volatile and a health check is not necessary.

    // Another reason could be for efficiency and gas savings:
    // Deferring the account status check until the end of the transaction can
    // be more gas-efficient, instead of performing the check immediately.

 // ------------------ DONE ------------------

    // [ASSIGNMENT]: is the vault status check always necessary? why?

    // As outlined in the whitepaper,
    // Upon receiving a requireVaultStatusCheck call, the EVC will determine whether the current execution context 
    // defers the checks and if so, it will defer checking the status for this vault
    // until the end of the execution context.
    // Otherwise, the vault status check will be performed immediately.

    // [ANSWER]
    // The vault status check might not always be necessary, and its necessity depends on the situation:
    // Vault Status Deferred Check:
    // If the modified function operates on a specific account (not the vault itself),
    // the vault status check might be deferred, and only deferred account status checks are performed.
    // In some situations, where the logic inside the modified function doesn't directly
    // affect the vault's state, the immediate vault status check might not be necessary.
    // It could also lead to efficiency and gas savings.
    // Similar to the account status check, deferring the vault status check until
    // the end of the transaction can be more gas-efficient, especially if 
    // multiple operations are performed within the same transaction.
    modifier withChecks(address account) {
        _;

        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

     // ------------------ DONE ------------------

    // [ASSIGNMENT]: can this function be used to authenticate the account for the sake of the borrow-related
    // operations? why?
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing? why do we pass address(0) to getCurrentOnBehalfOfAccount?

    // [ANSWER]

    // This function is sufficient to authenticate the account for borrow-related operations,
    // given the specific context in which it is used.
    // The function checks if the message sender (msg.sender) is the address of the EVC.
    // If it is, the function retrieves the current onBehalfOfAccount from the EVC
    // using getCurrentOnBehalfOfAccount and returns that address. 
    //  This is because vaults themselves don't understand sub-accounts or operators,
    // and defer their authorisation logic to the EVC (whitepaper).
    // This mechanism allows the system to use the authorization provided by the EVC
    // when the EVC calls functions in the system such as the true msg.sender.
    // In the context of borrowing operations, this can be useful to ensure that borrowing 
    // is done on behalf of the correct account.

    // If the answer to the above is "no", how could this function be modified to allow safe borrowing?

    // However, if there were specific requirements or changes in the system that
    // required modifications, one potential enhancement could be to introduce 
    // some extra verification methods.
    // For example, additional information could be passed, related to the borrowing operation, such as
    // the specific asset being borrowed, the loan amount, or any other relevant details. This additional information
    // could be used in conjunction with the onBehalfOfAccount
    // obtained from the EVC to perform more fine-grained authorization checks tailored to the borrowing scenario.
    // All these should ensure that the EVC should be able to get correct account information available for a given account.

    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) { 

            // function getCurrentOnBehalfOfAccount(address controllerToCheck)
            //  The caller of getCurrentOnBehalfOfAccount itself passes the vault it is
            // interested in via the controllerToCheck parameter.
            // When controllerToCheck is set to the zero address, the value returned is always false.

            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    // ------------------ DONE -------------------------

    // IVault
    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller?
    
    // [ANSWER]
    // Tis function is necessary because we need to disable the controller vault only after the user has 
    // fully repaid the loan taken from it.
    // if we were to disable the controller unconditionally before the user repays the loan,
    // the user can just keep the assets and flee ,
    // erasing the loan and damaging the health of the vault and the system.
    function disableController() external {
        evc.disableController(_msgSender());
    }

    // ---------------- DONE ----------------------------

    // [ASSIGNMENT]: provide a couple use cases for this function

    // [ANSWER]
    // A couple of potential use cases for this function are. 

    // 1. Considering Collaterals, Checking if an Account is Healthy (Collateral Evaluation)
    // The function could be used to dynamically evaluate the health of an account based on its collaterals.
    // For example, it might assess whether the total value of collaterals meets
    // certain requirements or if they fall within acceptable risk parameters. 
    // This could involve querying external Chainlink oracles for real world asset prices
    // or implementing custom logic to determine collateral health based on other implementations
    // such as aave's collateral health factor.

    // 2. Risk Management with External Data Sources
    // Oracle-Driven Risk Assessment
    // The function could be part of a risk management system where external data sources,
    // such as oracles, are used to assess the risk associated with the account.
    // The custom logic inside the function might involve fetching and analyzing external data to make some
    // decisions about the health of the account. This allows for a more dynamic and 
    // data-driven approach to risk management.

    // 3. Risk Management with Hardcoded Data
    // The function could be part of a risk management system where simple hardcoded data is used to assess the risk 
    // associated with the account based on its balance of other tokens and perhaps some simple formulas ?

    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the account health
        

        return IVault.checkAccountStatus.selector;
    }

    // ------------------ DONE -------------------------

    // [ASSIGNMENT]: provide a couple use cases for this function

    // [ANSWER]
    // 1. Custom Vault Health Assessment
    // The function could be used to perform a dynamic assessment of the health of a vault.
    // For example, it might evaluate whether the vault's total collateral meets certain requirements,
    // if it has breached any risk thresholds, or if it complies with specific constraints and standards set by the protocol
    // that uses the vault. Maybe the vault has a minimum collateralization ratio that it must maintain at all times.
    // Or maybe some tokens such as volatile meme tokens are not allowed to be used as collateral.
    // The custom logic inside the function enables the implementation of sophisticated checks customized 
    // to the specific requirements of the vault.
    // 2. Liquidity assessment. 
    // The function could also be used to assess the liquidity of the vault just like the previous use case.
    

    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?

        // [ANSWER]
        // maybe need access to initial snapshot of vault --> take snapshot once, store it on storeage variable and check against it here the current state with initial state
        // also upddate the snapshot whenever check is called

        // As mentioned in the whitepaper , the function might need access
        // to a snapshot of the initial state of the vault before a tx occures to properly evaluate its health.
        // In this case, the function could follow a pattern where, before performing any critical actions, 
        // that requires a vault status check
        // a snapshot of the vault's initial state is taken and stored in transient storage.
        // Subsequently, during the checkVaultStatus callback, this snapshot can be unpacked and 
        // compared against the current state of the vault, and return a success value, or revert if there is a violation.
        // This allows for a comprehensive evaluation of 
        // the vault's status, including potential changes made during the deferred checks.

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
