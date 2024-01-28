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
//  This modifier ensures that certain functions can only be called directly by the EVC. If called by any other entity, the function is redirected to the EVC, allowing the vault to operate under the assumption that specific checks are always deferred to the External Vault Contract. This will take care of routing the calls through the EVC, and the vault can operate under the assumption that the checks are always deferred.
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
If an account has not borrowed anything from the vault, there may be no need to perform an account status check.If the collateral provided by an account is considered low-risk,
and the vault has a high tolerance for that particular type of collateral, the vault may decide to skip account status checks for such accounts in a optimised way.

    // [ASSIGNMENT]: is the vault status check always necessary? why?
NO:vault status checks can be deferred based on the current execution context. This flexibility is useful for optimizing performance and scheduling checks when necessary.And for the 
the use of re-entrancy guards and the potential need for the call function to avoid re-entry issues when calling back into the vault's checkVaultStatus function.
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
this _msgSender function is designed to return the account address for the purpose of identifying the entity making the call.
No, for borrow-related users must be checked if the users account has any borrowcaps,also this msgsender its just for sake of the evc to take action onbehalfofaccount

    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
For safe borrowing must check the initial snapshot of the vault state before any operations have been performed.Must the borrowed assests below the vaule of Collateral.

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
Users account have limited actions on Controller, can only disableController when he can repay his debts back to the vault.Only the controller itself can call disableController on the EVC.No the EVC can't call the 
disableController without any reason, if any users is in debt, it shouldnt call this function under any circumstances.
    function disableController() external {
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
The vault will evaluate application-specific logic to determine whether or not the account is in an acceptable state.It checks the EVC call, accounts health to enable the collateral vaults.
It return a special magic success value
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
Vault checks ensures that maximum amount of assets that can be supplied or borrowed, as a risk minimisation. It takes a initial snapshot of the vault state before any operations have been performed.
Vaults must expose an external checkVaultStatus function. 
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
To take snapshot evaluate the vault status by unpacking the snapshot data stored in transient storage and compare it against the current state of the vault. So taking snapshot is important to consider initial vault state.
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
