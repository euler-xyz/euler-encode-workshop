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
    // [ANSWER]
    // Facilitates interaction between the WorkshopVault contract and the Ethereum Vault Connector (EVC) contract.
    // Determines if function calls should proceed normally (if called by EVC) or be rerouted through the EVC.
    // For calls not originating from EVC, forwards the call to EVC for processing and execution.
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
    // [ANSWER]: 
    // If the account's status is unchanged or already verified, further checks are redundant.
    // For operations that don't affect the account's state, such as read-only actions.
    // To optimize for gas efficiency and execution speed when status checks are irrelevant.

    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // [ANSWER]:
    // Essential for maintaining vault's state integrity and security, especially in state-changing transactions.
    // May be redundant in read-only operations or if the vault's status has already been validated.
    // Crucial for ensuring compliance with risk management protocols and regulatory standards.
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
    // [ANSWER]:
    // Suitable for identifying the correct account in the context of EVC operations.
    // Might not suffice for direct authentication in borrow-related operations.
    // Additional verification methods required to ensure proper permissions and criteria are met.

    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // [ANSWER]:
    // Implement additional checks to authenticate and validate the borrower’s identity and eligibility.
    // Ensure the borrowing account has the necessary permissions and meets borrowing criteria.
    // Modify to incorporate context-specific logic, considering both EVC and direct call scenarios.
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
    // [ANSWER]:
    // Allows account holders to manage or revoke controller privileges, ensuring flexibility.
    // Unconditional disabling can disrupt key operations, potentially compromising security.
    // Should be used judiciously and in a controlled manner to avoid unintended consequences.
    function disableController() external {
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // [ANSWER]:
    // Evaluates account's health or risk profile, crucial in lending and borrowing scenarios.
    // Verifies compliance with operational or regulatory requirements before executing transactions.
    // Assists in risk assessment and management, ensuring account's stability and integrity
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
    // [ANSWER]:
    // Ensures the operational integrity and security of the vault, safeguarding assets.
    // Verifies adherence to risk management and regulatory standards, maintaining platform stability.
    // Enforces global constraints such as supply/borrow caps for risk minimization.
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // [ANSWER]:
        // Implement a mechanism to capture the initial state of the vault at the start of a transaction.
        // Use the snapshot as a reference point to assess changes or anomalies during the status check.
        // Ensures the check is based on a verified state, enhancing reliability of the vault's health assessment.

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
