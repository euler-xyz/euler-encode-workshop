// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    error AccountUnhealthy();

    uint256 public borrowCap;
    uint256 public totalBorrowed;
    bytes private snapshotCreated;
    mapping(address account => uint256 assets) internal owed;

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
    // This modifier is designed to replicate the behavior of always invoking the vault through the EVC, using the Callback pattern. This ensures predictable behavior of the vault and the use of other EVC features.
    // Functionalities like patching, sub-accounts operators,etc; wouldn't be accessible. 
    // Additionally, this design choice helps mitigate security concerns, such as re-entrancy attacks.
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
    // If the address is non-meaningful there's no need to do status check. Also for gas optimization.
    // [ASSIGNMENT]: is the vault status check always necessary? why?
    // Yes, it is necessary to check the vault status for security and risk management purposes and avoid putting users funds at risk.
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
    // No, the _msg.sender() cannot be used for authentication. It needs extra layer of authentication.
    // [ASSIGNMENT]: if the answer to the above is "no", how this function could be modified to allow safe borrowing?
    // One approach could be to introduce a mapping that links accounts to a unique identifier for borrow-related operations. The function could check if the account has a valid identifier in the mapping.
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
    // To check if the user has fully repaid their loan otherwise the user could get away with the loan. No it's not safe to unconditionally disable the controller, we need to check if it has been repaid.
    function disableController() external {
        address msgSender = _msgSender();
        if (_debtOf(msgSender) == 0) {
            evc.disableController(msgSender);
        } else {
            revert OutstandingDebt();
        }
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // Use cases for this function could include: checking health status, assessing the risk levels of a user's account and other information to validate the user's operations.
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the account health
        uint256 liabilityAssets = _debtOf(account);

        if (liabilityAssets == 0) return;

        // in this simple example, let's say that it's only possible to borrow against
        // the same asset up to 90% of its value
        for (uint256 i = 0; i < collaterals.length; ++i) {
            if (collaterals[i] == address(this)) {
                uint256 collateral = _convertToAssets(balanceOf[account], false);
                uint256 maxLiability = (collateral * 9) / 10;

                if (liabilityAssets <= maxLiability) {
                    return;
                }
            }
        }

        revert AccountUnhealthy();

        return IVault.checkAccountStatus.selector;
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    // Use cases could include: checking if the vault has sufficient funds to fulfill a withdrawal request, the reserve ratio & the overall health of the vault.
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the vault health

        // [ASSIGNMENT]: what can be done if the vault status check needs access to the initial state of the vault in
        // order to evaluate the vault health?
        // We could store the initial state in a separate variable during the initialization of the contract. This variable can be accessed by the vault status check function.

        return IVault.checkVaultStatus.selector;
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 totalAssets = _totalAssets;
        uint256 ownAssets = balanceOf(owner);

        return _convertToShares(ownAssets, false) > totalAssets ? _convertToShares(totalAssets, false) : ownAssets;
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        uint256 totalAssets = totalAssets();
        uint256 ownerShares = balanceOf(owner);

        return _convertToAssets(ownerShares, false) > totalAssets ? _convertToShares(totalAssets, false) : ownerShares;
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        return roundUp
            ? assets.mulDivUp(totalSupply() + 1, _totalAssets + currentTotalBorrowed + 1)
            : assets.mulDivDown(totalSupply() + 1, _totalAssets + currentTotalBorrowed + 1);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _interestCalc();

        return roundUp
            ? shares.mulDivUp(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1)
            : shares.mulDivDown(totalAssets() + currentTotalBorrowed + 1, totalSupply() + 1);
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

    function createVaultSnapshot() internal {
        if (snapshot.length == 0) {
            snapshotCreated = doCreateVaultSnapshot();
        }
    }

    function doCreateVaultSnapshot() internal virtual returns (bytes memory) {
        (uint256 currentTotalBorrowed,) = _accrueInterest();

        return abi.encode(_convertToAssets(totalSupply(), false), currentTotalBorrowed);
    }

    // IWorkshopVault

    function borrow(uint256 assets, address receiver) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        receiver = getAccountOwner(receiver);

        _increaseOwed(msgSender, assets);

        emit Borrow(msgSender, receiver, assets);

        asset.safeTransfer(receiver, assets);

        _totalAssets -= assets;

        requireAccountAndVaultStatusCheck(msgSender);
    }

    function repay(uint256 assets, address receiver) external callThroughEVC nonReentrant {
        address msgSender = _msgSender();

        // sanity check: the receiver must be under control of the EVC. otherwise, we allowed to disable this vault as
        // the controller for an account with debt
        if (!isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        require(assets != 0, "ZERO_ASSETS");

        asset.safeTransferFrom(msgSender, address(this), assets);

        _totalAssets += assets;

        _decreaseOwed(receiver, assets);

        emit Repay(msgSender, receiver, assets);

        requireAccountAndVaultStatusCheck(address(0));
    }

    function pullDebt(address from, uint256 assets) external callThroughEVC nonReentrant returns (bool) {
        address msgSender = _msgSenderForBorrow();

        // sanity check: the account from which the debt is pulled must be under control of the EVC.
        // _msgSenderForBorrow() checks that `msgSender` is controlled by this vault
        if (!isControllerEnabled(from, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        require(assets != 0, "ZERO_AMOUNT");
        require(msgSender != from, "SELF_DEBT_PULL");

        _decreaseOwed(from, assets);
        _increaseOwed(msgSender, assets);

        emit Repay(msgSender, from, assets);
        emit Borrow(msgSender, msgSender, assets);

        requireAccountAndVaultStatusCheck(msgSender);

        return true;
    }

    function liquidate(
        address violator,
        address collateral,
        uint256 repayAssets
    ) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();

        if (msgSender == violator) {
            revert SelfLiquidation();
        }

        if (repayAssets == 0) {
            revert RepayAssetsInsufficient();
        }

        
        if (isAccountStatusCheckDeferred(violator)) {
            revert ViolatorStatusCheckDeferred();
        }

        
        if (!isControllerEnabled(violator, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        uint256 seizeShares = _calculateSharesToSeize(violator, collateral, repayAssets);

        _decreaseOwed(violator, repayAssets);
        _increaseOwed(msgSender, repayAssets);

        emit Repay(msgSender, violator, repayAssets);
        emit Borrow(msgSender, msgSender, repayAssets);

        if (collateral == address(this)) {
            
            if (!isCollateralEnabled(violator, collateral)) {
                revert CollateralDisabled();
            }

            balanceOf[violator] -= seizeShares;
            balanceOf[msgSender] += seizeShares;

            emit Transfer(violator, msgSender, seizeShares);
        } else {
            
            liquidateCollateralShares(collateral, violator, msgSender, seizeShares);

            
            forgiveAccountStatusCheck(violator);
        }

        requireAccountAndVaultStatusCheck(msgSender);
    }
}
