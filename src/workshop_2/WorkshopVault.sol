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
    // [ANSWER]: The purpose of this modifier is to ensure that the caller is the EVC. If the caller is not the EVC, it
    // makes use of the callback functionality to make EVC call the functions in this vault.
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
    // [ANSWER]: If the account has not taken up any liability, there is no need to ensure health / solvency of the
    // account. If the account only supplies assets as collateral (for yield) and not taking out any debt, there is no
    // need to check as the account would never be in violation.
    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // [ANSWER]: Vault status checks are not always necessary, if there is no business logic to be enforced on the
    // vault. For example, if the vault does not have a supply / borrow limit there is nothing to check for the vault
    // itself.
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
    // [ANSWER]: No
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // [ANSWER]: We need to check if this vault is enabled as a controller of that particular account
    // before allowing borrow-related operations.
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
    // [ANSWER]: It's necessary so that the account can be released from this controller and be under the control of
    // another controller in the future. In the EVC, each account can only have at most one controller at any point
    // in time. Without this function, an account will permanently be under the control of a certain controller, which
    // in malicious cases, could pose risks of asset loss.
    // It's not safe to unconditionally disable the controller. The controller should check that the account has no more
    // outstanding liabilities before allowing it to be disabled.
    function disableController() external {
        evc.disableController(_msgSender());
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // [ANSWER]: A use case could be to check if the liabilities exceed the collateral (health of the account).
    // Another use case could be to see if the account is blacklisted, in the case of a permissioned vault.
    // Yet another use case could be to check if an account is using a collateral that was recently de-listed (was
    // previously eligible to be used as collateral but has been disallowed since).
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
    // 1. To update the interest rate
    // 2. To check if the supply cap is exceeded
    // 3. To check if the borrow cap is exceeded
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // [ANSWER]: We can take a snapshot at the beginning of the transaction, and place it in memory instead of
        // storage for gas savings. Then reference the snapshot in this function to perform calculations against the
        // current state.

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
