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
    //        And also to check/execute and custom logic.
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

    // IVault
    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller?

    // Answer : Since, the controller has full control of the account and can act on behalf of the user once the user borrows from the vault
    // a function like this becomes necessary so that the controller can be disabled once the user returns the borrowed amount for the safety of the user.
    //          
    // No, its not safe to unconditionally disable it, if done so the user could get away with the borrowed amount without returning it.
    // Hence, it becomes important to check the condition that the user does not have any liabilities
    // and has returned the borrowed amount before calling this function and disabling the controller
    // Its best to use this function only when required as improper use may lead to unexpected states/results.
    function disableController() external {
        evc.disableController(_msgSender());
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
