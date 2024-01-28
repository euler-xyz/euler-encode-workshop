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

    // [ASSIGNMENT]: what is the purpose of this modifier? This modifier ensures that specific functions can only be called by the EVC contract. It verifies the sender's address against the EVC address before allowing the function execution. This prevents unauthorized access and maintains control over sensitive operations managed by the EVC.
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

    // [ASSIGNMENT]: why the account status check might not be necessary in certain situations? This check might not be necessary in situations where only the vault status is important and the account's overall health isn't relevant. This could occur when evaluating the vault's health in isolation or during specific operations independent of individual accounts.
    // [ASSIGNMENT]: is the vault status check always necessary? why? This check is always necessary because the vault's health directly impacts the overall system stability and the safety of user funds. Checking the vault's status ensures it's operating within acceptable parameters before allowing sensitive operations like deposits or withdrawals.
    modifier withChecks(address account) {
        _;

        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    // [ASSIGNMENT]: can this function be used to authenticate the account for the sake of the borrow-related
    // operations? why? No, this function cannot directly authenticate the account for borrow-related operations. It only determines the actual message sender in scenarios where the EVC is acting on behalf of another account. Borrow operations typically require additional checks and approvals specific to the borrowing functionality.
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing? To enable safe borrowing using this function, you could add a dedicated check within the borrow function itself. This check could verify the account's borrowing capacity, collateralization ratio, and other relevant parameters before authorizing the borrow request.
    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    // IVault
    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller? Disabling the controller can be necessary in emergency situations where unexpected behavior threatens the system's stability. However, it's essential to approach this action with caution. Unconditionally disabling the controller removes a crucial control mechanism and should only be considered as a last resort after exhausting other options.
    function disableController() external {
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function. 
    // checkAccountStatus: This function can be used by the EVC during various situations:
    //    - During borrow approvals to assess the account's ability to sustain additional debt.
    //    - As part of periodic risk assessments to monitor the overall health of individual accounts.
    //    - To trigger specific actions (e.g., margin calls) when an account's health deteriorates.

    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the account health

        return IVault.checkAccountStatus.selector;
    }

    // [ASSIGNMENT]: provide a couple use cases for this function. 
    //  checkVaultStatus: This function can be used for:
    //    - Evaluating the vault's overall health and liquidity before allowing large deposits or withdrawals.
    //    - Identifying potential risks within the vault and initiating countermeasures to protect user funds.
    //    - Triggering system-wide adjustments (e.g., interest rate changes) based on the vault's performance.

    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health? 
        // If the vault status check needs access to the initial state of the vault, we can implement the following solution:
        // - Store the initial state (e.g., total assets, liabilities, etc.) in a separate storage variable when the vault is deployed.
        // - Access this initial state variable within the checkVaultStatus function to compare the current state against the baseline and evaluate the vault's health evolution.

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
