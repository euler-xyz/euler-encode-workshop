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
    // [ANSWER]:
    //  Enables the interaction between the WorkshopVault contract and the Ethereum Vault Connector (EVC) contract.
    //  Checks whether function calls should follow their regular course (when invoked by EVC) or be redirected through the EVC.
    //  If the calls do not originate from the EVC, they are directed to the EVC for handling and execution.
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
    // If the account's status remains unchanged or is already verified, additional checks are unnecessary.
    // Applies to operations that have no impact on the account's state, such as read-only actions.
    // Aimed at optimizing gas efficiency and execution speed in situations where status checks are irrelevant.

    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // [ANSWER]:
    // Crucial for upholding the integrity and security of the vault's state, particularly in transactions that alter the state.
    // Might be unnecessary in read-only operations or if the vault's status has been previously validated.
    // Vital for ensuring adherence to risk management protocols and regulatory standards.

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
    // Appropriate for identifying the correct account within the scope of EVC operations.
    // May not be adequate for direct authentication in borrow-related operations.
    // Supplementary verification methods are necessary to guarantee proper permissions and adherence to criteria.

    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // [ANSWER]:
    // Introduce extra checks for authenticating and validating the borrower's identity and eligibility.
    // Verify that the borrowing account possesses the required permissions and fulfills borrowing criteria.
    // Adjust to include context-specific logic, taking into account both EVC and direct call scenarios.
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
    // Empowers account holders to oversee or revoke controller privileges, ensuring flexibility.
    // Indiscriminate disabling may disrupt crucial operations, posing potential security risks.
    // Should be employed with discretion and under controlled conditions to prevent unintended consequences.
    function disableController() external {
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // [ANSWER]:
    // Assesses the health or risk profile of the account, a critical aspect in lending and borrowing scenarios.
    // Confirms compliance with operational or regulatory requirements prior to transaction execution.
    // Facilitates risk assessment and management, safeguarding the stability and integrity of the account.

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
    // Safeguards assets by ensuring the operational integrity and security of the vault.
    // Validates compliance with risk management and regulatory standards, contributing to platform stability.
    // Enforces global constraints, such as supply/borrow caps, to minimize risk.

    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // [ANSWER]:
        // Introduce a mechanism to record the initial state of the vault when a transaction begins.
        // Utilize the snapshot as a reference point for evaluating changes or anomalies during the status check.
        // Ensures that the check is grounded in a verified state, thereby enhancing the reliability of the vault's health assessment.

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
