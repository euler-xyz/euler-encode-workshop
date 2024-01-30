// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {

    using FixedPointMathLib for uint256;

    uint256 public totalBorrowed;
    uint256 internal _totalAssets;
    mapping(address account => uint256 assets) internal owed;
    IEVC internal immutable evc;
    bytes private snapshot;

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
    }

    // [ASSIGNMENT]: what is the purpose of this modifier?
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
    // [ASSIGNMENT]: is the vault status check always necessary? why?
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
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
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
    function disableController() external {
        address msgSender = _msgSender();
        if (_debtOf(msgSender) == 0) {
            evc.disableController(_msgSender());
        } else {
            revert();
        }
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        uint256 liabilityAssets = _debtOf(account);

        if (liabilityAssets == 0) return IVault.checkAccountStatus.selector;

        for (uint256 i = 0; i < collaterals.length; ++i) {
            if (collaterals[i] == address(this)) {
                uint256 collateral = _convertToAssets(balanceOf(account), false);
                uint256 maxLiability = (collateral * 9) / 10;

                if (liabilityAssets <= maxLiability) {
                    return IVault.checkAccountStatus.selector;
                }
            }
        }
        revert();
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?

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
    function borrow(uint256 assets, address receiver) external callThroughEVC {
        IERC20 _asset = ERC20(asset());
        address msgSender = _msgSenderForBorrow();
        createVaultSnapshot();
        require(assets != 0, "ZERO_ASSETS");
        receiver = getAccountOwner(receiver);        
        _asset.transfer(receiver, assets);
        _increaseOwed(msgSender, assets);
        _totalAssets -= assets;
    }
    
    function repay(uint256 assets, address receiver) external {
        IERC20 _asset = ERC20(asset());
        address msgSender = _msgSender();
        if (!evc.isControllerEnabled(receiver, address(this))) {
            revert();
        }
        createVaultSnapshot();
        require(assets != 0, "ZERO_ASSETS");
        _asset.transferFrom(msgSender, address(this), assets);
        _decreaseOwed(receiver, assets);
        _totalAssets += assets;
    }
    
    function pullDebt(address from, uint256 assets) external returns (bool) {
        address msgSender = _msgSenderForBorrow();
        if (!evc.isControllerEnabled(from, address(this))) {
            revert();
        }
        createVaultSnapshot();
        require(assets != 0, "ZERO_AMOUNT");
        require(msgSender != from, "SELF_DEBT_PULL");
        _decreaseOwed(from, assets);
        _increaseOwed(msgSender, assets);

        return true;
    }

    function liquidate(address violator, address collateral) external {
        address msgSender = _msgSender();

        if (!evc.isControllerEnabled(msgSender, address(this))) {
            revert("Not authorized to liquidate");
        }

        uint256 collateralAmount = balanceOf(violator);

        require(collateralAmount > 0, "No collateral to liquidate");

        _transfer(violator, msgSender, collateralAmount);
    }

    function createVaultSnapshot() internal {
        uint256 currentTotalBorrowed;
        uint256 currentInterestAccumulator;
        (currentTotalBorrowed, currentInterestAccumulator) = _accrueInterest();

        if (snapshot.length == 0) {
            snapshot = abi.encode(_convertToAssets(totalSupply(), false), currentTotalBorrowed);
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
            revert();
        }

        return sender;
    }

    function getAccountOwner(address account) internal view returns (address owner_out) {
        try evc.getAccountOwner(account) returns (address _owner) {
            owner_out = _owner;
        } catch {
            owner_out = account;
        }
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 totAssets = totalAssets();
        uint256 ownerAssets = _convertToAssets(balanceOf(owner), false);

        return ownerAssets > totAssets ? totAssets : ownerAssets;
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        uint256 totAssets = totalAssets();
        uint256 ownerShares = balanceOf(owner);

        return _convertToAssets(ownerShares, false) > totAssets ? _convertToShares(totAssets, false) : ownerShares;
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return roundUp
            ? assets.mulDivUp(totalSupply() + 1, totalAssets() + currentTotalBorrowed + 1)
            : assets.mulDivDown(totalSupply() + 1, totalAssets() + currentTotalBorrowed + 1);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return roundUp
            ? shares.mulDivUp(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1)
            : shares.mulDivDown(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1);
    }

    function _debtOf(address account) internal view virtual returns (uint256) {
        return owed[account];
    }

    function _increaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) + assets;
        totalBorrowed += assets;
    }

    function _decreaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) - assets;
        totalBorrowed -= assets;
    }

    function _accrueInterest() internal virtual returns (uint256, uint256) {
        return (totalBorrowed, 0);
    }

    function _accrueInterestCalculate() internal view virtual returns (uint256, uint256, bool) {
        return (totalBorrowed, 0, false);
    }

    function _updateInterest() internal virtual {}
}
