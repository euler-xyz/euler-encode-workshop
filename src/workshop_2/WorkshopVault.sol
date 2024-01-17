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
    // [ANSWER]: The callThroughEVC modifier is designed to ensure that certain functions can only be called through the evc. 
    // If the msg.sender is the evc itself, the function proceeds normally. Otherwise, it delegates the call to the evc, which then executes the function. 
    // This is likely a security or control mechanism to ensure that certain sensitive operations can only be performed through the evc.
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
    // [ANSWER]:The account status check might not be necessary in situations where the operation does not involve specific user accounts, 
    // such as global configurations or operations that affect the vault as a whole.
    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // [ANSWER]:The vault status check, on the other hand, is likely always necessary to ensure the overall health and integrity of the vault. 
    // This is crucial for maintaining trust and security in the system, especially in operations that could affect all users or the vault's stability.
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
    // [ANSWER]: As it stands, _msgSender() might not be sufficient for secure authentication in borrow-related operations because it can 
    // return an account on behalf of which the evc is acting. This could be manipulated or misused.
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // [ANSWER]: To modify it for safe borrowing, additional checks or a different mechanism to authenticate the real initiator of the transaction should be implemented. 
    // This could involve verifying signatures or adding more stringent checks to ensure that the account requesting the borrow is indeed the one authorized to do so.
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
    // [ANSWER]: This function is necessary to provide a way to disable the controller of the vault, 
    // which could be a critical action in certain scenarios, such as a security breach or a major operational change.
    // Unconditionally disabling the controller might not be safe as it could lead to misuse or unintended consequences. It should ideally have safeguards, 
    // such as requiring multiple confirmations, a time lock, or being callable only under specific conditions.
    function disableController() external {
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // [ANSWER]: This function could be used to assess the health or status of an account, such as checking for solvency, 
    // compliance with risk parameters, or eligibility for certain operations like borrowing or staking.
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
    // [ANSWER]: This function could be used to evaluate the overall health of the vault, like checking liquidity levels, overall risk exposure, 
    // or compliance with regulatory requirements.
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // [ANSWER]: If the vault status check requires access to the initial state, one approach could be to maintain a historical record or 
        // snapshot of the vault's state at key points in time. This could involve storing state variables that represent the vault's condition at these moments, allowing the check function to compare current and past states to assess health or changes over time.
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
