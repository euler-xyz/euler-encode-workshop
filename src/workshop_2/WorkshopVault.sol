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

    modifier withChecks(address account) {
        _;

        if (account == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    function _msgSender() internal view virtual override returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            return onBehalfOfAccount;
        } else {
            return msg.sender;
        }
    }

    // IVault
    function disableController() external override{
        evc.disableController(_msgSender());
    }

    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual override returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // [TODO]: Write some custom logic evaluating the account health
        // [TODO]: Check if it stays above a minimum threshold after considering the intended borrow amount.
        // [TODO]: Compare the existing debt to the maximum allowed debt ratio or absolute limit.
        // [TODO]: Consider factors like past repayment behavior and delinquencies.

        return IVault.checkAccountStatus.selector;
    }

    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // [TODO]: Write some custom logic evaluating the vault health

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
    function borrow(uint256 assets, address receiver) external {
       require(isBorrowingAllowed(_msgSender(), assets), "Borrowing not allowed");

       updateCollateralizationRatio(_msgSender(), assets);

       _asset.safeTransfer(receiver, assets);
       _borrowed[_msgSender()] += assets;
       // [TODO:] add interest accrual logic here

       emit Borrowed(_msgSender(), assets);
    }

    function repay(uint256 assets, address receiver) external {
       require(_asset.balanceOf(_msgSender()) >= assets, "Insufficient assets for repayment");

       updateCollateralizationRatio(_msgSender(), -assets); // Negative value for repayment

       _asset.safeTransferFrom(_msgSender(), receiver, assets);
       _borrowed[_msgSender()] -= assets;
       // [TODO] Calculate interest accrued

       emit Repaid(_msgSender(), assets);
    }

    function pullDebt(address from, uint256 assets) external returns (bool) {
       require(_borrowed[from] >= assets, "Insufficient debt to pull");

       // [TODO]: Transfer collateral to caller to cover debt

       _borrowed[from] -= assets;
       updateCollateralizationRatio(from, -assets);

       emit DebtPulled(from, assets);

       return true;
    }

    function liquidate(address violator, address collateral) external {
       require(isLiquidationAllowed(violator), "Liquidation not allowed");

       // [TODO]: Seize collateral

       // [TODO]: Use seized collateral to repay debt

       // [TODO]: Distribute any surplus to liquidator or other stakeholders

       // 5. Emit event for liquidation
       emit Liquidated(violator, collateral);
   }
}
