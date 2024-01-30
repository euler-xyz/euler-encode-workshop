// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    using Math for uint256;

    IEVC internal immutable evc;

    uint96 internal interestRate;
    uint256 internal lastInterestUpdate;
    uint256 internal totalBorrowed;
    uint256 internal _totalAssets;

    mapping(address => uint256) public userBorrowedAmounts;
    mapping(ERC4626 => uint256) public collateralFactors;

    event Borrow(address indexed caller, address indexed owner, uint256 assets);
    event Repay(address indexed caller, address indexed receiver, uint256 assets);

    error ControllerDisabled();

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
        lastInterestUpdate = block.timestamp;
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

    function _msgSenderForBorrow() internal view returns (address) {
        address sender = msg.sender;
        bool controllerEnabled;

        if (sender == address(evc)) {
            (sender, controllerEnabled) = evc.getCurrentOnBehalfOfAccount(address(this));
        } else {
            controllerEnabled = evc.isControllerEnabled(sender, address(this));
        }

        if (!controllerEnabled) {
            revert ControllerDisabled();
        }

        return sender;
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        return _convert(assets, roundUp, totalSupply() + 1, _totalAssets + totalBorrowed + 1);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        return _convert(shares, roundUp, _totalAssets + totalBorrowed + 1, totalSupply() + 1);
    }

    function _convert(uint256 from, bool roundUp, uint256 fromBase, uint256 toBase) internal pure returns (uint256) {
        return roundUp
            ? from.mulDiv(toBase, fromBase, Math.Rounding.Ceil)
            : from.mulDiv(toBase, fromBase, Math.Rounding.Floor);
    }

    function totalAssets() public view override returns (uint256) {
        return _totalAssets + totalBorrowed;
    }

    function disableController() external {
        evc.disableController(_msgSender());
    }

    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        return IVault.checkAccountStatus.selector;
    }

    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        return IVault.checkVaultStatus.selector;
    }

    // IWorkshopVault

    function borrow(uint256 assets, address receiver) external callThroughEVC withChecks(_msgSenderForBorrow()) {
        address msgSender = _msgSenderForBorrow();

        require(assets != 0, "ZERO_ASSETS");

        receiver = evc.getAccountOwner(receiver);

        emit Borrow(msgSender, receiver, assets);

        ERC20(asset()).transfer(receiver, assets);

        _increaseBorrowedAmount(msgSender, assets);
        _totalAssets -= assets;
    }

    function repay(uint256 assets, address receiver) external callThroughEVC withChecks(address(0)) {
        address msgSender = _msgSender();

        if (!evc.isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }

        require(assets != 0, "ZERO_ASSETS");

        emit Repay(msgSender, receiver, assets);

        ERC20(asset()).transferFrom(msgSender, address(this), assets);

        _decreaseBorrowedAmount(receiver, assets);
        _totalAssets += assets;
    }

    function pullDebt(
        address from,
        uint256 assets
    ) external callThroughEVC withChecks(_msgSenderForBorrow()) returns (bool) {
        address msgSender = _msgSenderForBorrow();

        if (!evc.isControllerEnabled(from, address(this))) {
            revert ControllerDisabled();
        }

        require(assets != 0, "ZERO_AMOUNT");
        require(msgSender != from, "SELF_DEBT_PULL");

        _decreaseBorrowedAmount(from, assets);
        _increaseBorrowedAmount(msgSender, assets);

        emit Repay(msgSender, from, assets);
        emit Borrow(msgSender, msgSender, assets);

        return true;
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

    function _accrueInterest() internal virtual returns (uint256, uint256) {
        (uint256 currentTotalBorrowed, bool shouldUpdate) = _accrueInterestCalculate();

        if (shouldUpdate) {
            totalBorrowed = currentTotalBorrowed;
            lastInterestUpdate = block.timestamp;
        }

        return (currentTotalBorrowed, interestRate);
    }

    function _accrueInterestCalculate() internal view virtual returns (uint256, bool) {
        uint256 timeElapsed = block.timestamp - lastInterestUpdate;
        uint256 oldTotalBorrowed = totalBorrowed;

        if (timeElapsed == 0) {
            return (oldTotalBorrowed, false);
        }

        uint256 interestAccumulator = (interestRate * timeElapsed) / 1 days;

        uint256 newTotalBorrowed = oldTotalBorrowed + (oldTotalBorrowed * interestAccumulator) / 1e18;

        return (newTotalBorrowed, true);
    }

    function _increaseBorrowedAmount(address account, uint256 assets) internal virtual {
        userBorrowedAmounts[account] += assets;
        totalBorrowed += assets;
    }

    function _decreaseBorrowedAmount(address account, uint256 assets) internal virtual {
        userBorrowedAmounts[account] -= assets;
        totalBorrowed -= assets;
    }

    function _debtOf(address account) public view returns (uint256) {
        (uint256 currentTotalBorrowed,) = _accrueInterestCalculate();
        uint256 debt = userBorrowedAmounts[account];
        if (debt == 0) return 0;
        return (debt * currentTotalBorrowed) / (totalBorrowed + 1);
    }

    function liquidate(address violator, address collateral) external override {}
}
