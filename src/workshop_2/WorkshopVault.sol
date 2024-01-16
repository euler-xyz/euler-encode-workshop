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
    //  Centralizes interaction and control: All function calls to the contract, except those coming from the Ethereum Vault Connector (EVC), are routed through the EVC. This establishes the EVC as a central authority for managing and potentially intervening in vault-related actions.
    //  Improves security and composability: Routing calls through the EVC allows for monitoring and blocking unauthorized actions. Implement consistent governance and risk management practices across multiple vaults. Ensure that external rules and regulations are followed. Allow for the modular composition of vaults with other DeFi protocols.

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
    //  Frequent status checks can slow down user interactions, potentially causing delays or transaction failures.

    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // [ANSWER]:
    //  Vault status checks are generally required to ensure the vault's integrity and proper operation. However, in some cases, such as read-only operations or when the vault's status has recently been verified and no state-changing transactions have occurred, the vault status check may be unnecessary. Typically, this check is critical for maintaining the vault's security and consistency, particularly for state-changing operations.

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
    //  No, The _msgSender() function in the context of the EVC, which is overridden to return the account on behalf of which the EVC is operating, may be used to authenticate the account for borrow-related operations. It assists in identifying the correct account that initiated the borrow request. However, relying solely on this function may not be sufficient to ensure safe borrowing. Additional validations and checks should be implemented to ensure that the account has the necessary permissions and meets all of the borrowing criteria.

    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // [ANSWER]: 
    //  Implement a mechanism in which the borrowing account specifies a future time when the borrowing request can be executed, preventing unauthorized access.

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
    //  The disableController function allows for emergency control revocation to protect against compromised or dysfunctional controllers; however, unconditional disabling may result in functionality loss.

    function disableController() external {
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // [ANSWER]:
    //  1. Risk Assessment before lending: Lenders can use this feature to assess a borrower's account health before approving a loan request.
    //  2. Liquidationn Triggering: If an account's health deteriorates below acceptable thresholds (for example, the collateral value falls too low), this function can initiate liquidation procedures.
    
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
    //  1. Overall Health Monitoring: Provides a comprehensive assessment of the vault's financial health, including: solvency, collateralization levels, liquidity and profitability.
    //  2. Compliance Verification:Checks if the vault adheres to regulatory requirements or internal governance rules, such as: collateralization ratios, risk exposure limits, anti-money laundering (AML) and know-your-customer (KYC) compliance
    
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // [ANSWER]:
        //  Accessing the initial vault state for checks can be tricky. One approach is to store it directly on-chain at deployment, update it through events, or retrieve it from trusted sources like oracles. Alternatively, past event history or off-chain calculations could be used. Be mindful of security, gas costs, and potential centralization concerns when choosing your method.

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
