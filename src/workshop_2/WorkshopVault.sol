// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "evc/interfaces/IVault.sol";
import "./IWorkshopVault.sol";
import "./IQuoterV2.sol";

contract WorkshopVault is ERC4626, IVault, IWorkshopVault {
    using Math for uint256;

    IEVC internal immutable evc;

    uint96 internal interestRate;
    uint256 internal lastInterestUpdate;
    uint256 internal interestAccumulator;

    uint256 internal constant COLLATERAL_FACTOR_SCALE = 100;
    uint256 internal constant MAX_LIQUIDATION_INCENTIVE = 20;
    uint256 internal constant TARGET_HEALTH_FACTOR = 125;
    uint256 internal constant BASE_INTEREST_RATE = 100; // 1.00% as base interest rate in basis points (0.01%)
    uint256 internal constant MAX_INTEREST_RATE = 500; // 5.00% AS base interest rate in basis points (0.05%)
    uint256 internal constant ONE = 1e27;

    uint256 internal _totalAssets;
    uint256 public totalBorrowed;
    uint256 public borrowCap;
    uint256 public supplyCap;
    address public owner;
    bytes private snapshot;

    IQuoterV2 public oracle;

    ERC20 public referenceAsset;

    mapping(address account => uint256 assets) owed;

    mapping(address account => uint256) internal userInterestAccumulator;
    mapping(ERC4626 vault => uint256) internal collateralFactor;

    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event SupplyCapSet(uint256 newSupplyCap);
    event BorrowCapSet(uint256 newBorrowCap);
    event Borrow(address indexed caller, address indexed owner, uint256 assets);
    event Repay(address indexed caller, address indexed receiver, uint256 assets);

    error OutstandingDebt();
    error SnapshotNotTaken();
    error SupplyCapExceeded();
    error BorrowCapExceeded();
    error ControllerDisabled();
    error SharesSeizureFailed();
    error InvalidCollateralFactor();
    error AccountUnhealthy();
    error SelfLiquidation();
    error RepayAssetsInsufficient();
    error ViolatorStatusCheckDeferred();
    error CollateralDisabled();
    error RepayAssetsExceeded();
    error NoLiquidationOpportunity();
    error VaultStatusCheckDeferred();

    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        evc = _evc;
        oracle = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e); // IQuoterV2 Ethereum Address
        referenceAsset = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7); // USDT Ethereum Address
        owner = msg.sender;
        lastInterestUpdate = block.timestamp;
        interestAccumulator = ONE;
        emit OwnershipTransferred(address(0), msg.sender);
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

    modifier onlyOwner() virtual {
        require(msg.sender == owner, "UNAUTHORIZED");

        _;
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

    // IVault
    // [ASSIGNMENT]: why this function is necessary? is it safe to unconditionally disable the controller?
    function disableController() external {
        address msgSender = _msgSender();
        if (_debtOf(msgSender) == 0) {
            evc.disableController(msgSender);
        } else {
           revert OutstandingDebt();
        }
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual returns (bytes4 magicValue) {
        // 1. Check whether it's the EVC calling
        require(msg.sender == address(evc), "only evc can call this");

        // 2. Check whether checks are in progress
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // 3. Calculate the collateral and liability value
        if (_debtOf(account) > 0) {
            (, uint256 liabilityValue, uint256 collateralValue) = _calculateLiabilityAndCollateral(account, collaterals);

            if (liabilityValue > collateralValue) {
                revert AccountUnhealthy();
            }
        }

        // 4. Return the magic value if the account is healthy
        return IVault.checkAccountStatus.selector;
    }

    function createVaultSnapshot() internal {
        uint256 currentTotalBorrowed;
        uint256 currentInterestAccumulator;
        (currentTotalBorrowed, currentInterestAccumulator) = _accrueInterest();

        if (snapshot.length == 0) {
            snapshot = abi.encode(_convertToAssets(totalSupply(), false), currentTotalBorrowed);
        }
    }

    // [ASSIGNMENT]: provide a couple use cases for this function
    function checkVaultStatus() public virtual returns (bytes4 magicValue) {
        // 1. Check whether it's the EVC calling
        require(msg.sender == address(evc), "only evc can call this");

        // 2. Check whether checks are in progress
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // 3. Ensure that the snapshot status is valid
        if (snapshot.length == 0) revert SnapshotNotTaken();

        // 4. Compare the snapshot with the current vault state (invariant check, supply/borrow cap enforcement, etc.).
        // Ensure your vault is sound as a whole.
        _updateInterest();

        (uint256 initialSupply, uint256 initialBorrowed) = abi.decode(snapshot, (uint256, uint256));
        uint256 finalSupply = _convertToAssets(totalSupply(), false);
        uint256 finalBorrowed = totalBorrowed;

        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert SupplyCapExceeded();
        }

        if (borrowCap != 0 && finalBorrowed > borrowCap && finalBorrowed > initialBorrowed) {
            revert BorrowCapExceeded();
        }

        // 5. Clear the old snapshot
        delete snapshot;

        // 6. Return the magic value if the vault is healthy
        return IVault.checkVaultStatus.selector;
    }

    function deposit(
        uint256 _assets,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 shares) {
        createVaultSnapshot();
        require((shares = _convertToShares(_assets, false)) != 0, "ZERO_SHARES");
        _totalAssets = _totalAssets + _assets;
        return super.deposit(_assets, receiver);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override callThroughEVC withChecks(address(0)) returns (uint256 assets) {
        createVaultSnapshot();
        _totalAssets = _totalAssets + _convertToAssets(shares, true);
        return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 _assets,
        address receiver,
        address _owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 shares) {
        createVaultSnapshot();
        _totalAssets = _totalAssets - _assets;
        return super.withdraw(_assets, receiver, _owner);
    }

    function maxWithdraw(address _owner) public view override returns (uint256) {
        uint256 totAssets = _totalAssets;
        uint256 ownerAssets = _convertToAssets(balanceOf(_owner), false);
        return ownerAssets > totAssets ? totAssets : ownerAssets;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address _owner
    ) public virtual override callThroughEVC withChecks(owner) returns (uint256 assets) {
        createVaultSnapshot();
        require((assets = _convertToAssets(shares, false)) != 0, "ZERO_ASSETS");
        _totalAssets = _totalAssets - assets;
        return super.redeem(shares, receiver, _owner);
    }

    function maxRedeem(address _owner) public view override returns (uint256) {
        uint256 totAssets = _totalAssets;
        uint256 ownerShares = balanceOf(_owner);
        return _convertToAssets(ownerShares, true) > totAssets ? _convertToShares(totAssets, true) : ownerShares;
    }

    function transfer(
        address to,
        uint256 value
    ) public virtual override (ERC20, IERC20) callThroughEVC withChecks(_msgSender()) returns (bool) {
        createVaultSnapshot();
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override (ERC20, IERC20) callThroughEVC withChecks(from) returns (bool) {
        createVaultSnapshot();
        return super.transferFrom(from, to, value);
    }

    function setSupplyCap(uint256 newSupplyCap) external onlyOwner {
        supplyCap = newSupplyCap;
        emit SupplyCapSet(newSupplyCap);
    }

    function setBorrowCap(uint256 newBorrowCap) external onlyOwner {
        borrowCap = newBorrowCap;
        emit BorrowCapSet(newBorrowCap);
    }

    function setCollateralFactor(ERC4626 vault, uint256 _collateralFactor) external onlyOwner {
        if (_collateralFactor > COLLATERAL_FACTOR_SCALE) {
            revert InvalidCollateralFactor();
        }

        collateralFactor[vault] = _collateralFactor;
    }

    function _increaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) + assets;
        totalBorrowed += assets;
        userInterestAccumulator[account] = interestAccumulator;
    }

    function _decreaseOwed(address account, uint256 assets) internal virtual {
        owed[account] = _debtOf(account) - assets;
        totalBorrowed -= assets;
        userInterestAccumulator[account] = interestAccumulator;
    }

    // IWorkshopVault

    function borrow(uint256 assets, address receiver) external callThroughEVC withChecks(_msgSenderForBorrow()) {

        IERC20 _asset = ERC20(asset());

        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();
        require(assets != 0, "ZERO_ASSETS");
        
        receiver = getAccountOwner(receiver);
        
        emit Borrow(msgSender, receiver, assets);

        _asset.transfer(receiver, assets);

        _increaseOwed(msgSender, assets);
        _totalAssets -= assets;
    }

    function repay(uint256 assets, address receiver) external callThroughEVC withChecks(address(0)) {

        IERC20 _asset = ERC20(asset());

        address msgSender = _msgSender();
        
        if (!evc.isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();
        require(assets != 0, "ZERO_ASSETS");

        emit Repay(msgSender, receiver, assets);

        _asset.transferFrom(msgSender, address(this), assets);

        _decreaseOwed(receiver, assets);
        _totalAssets += assets;

    }

    function pullDebt(address from, uint256 assets) external callThroughEVC withChecks(_msgSenderForBorrow()) returns (bool) {

        address msgSender = _msgSenderForBorrow();

        if (!evc.isControllerEnabled(from, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        require(assets != 0, "ZERO_AMOUNT");
        require(msgSender != from, "SELF_DEBT_PULL");

        _decreaseOwed(from, assets);
        _increaseOwed(msgSender, assets);

        emit Repay(msgSender, from, assets);
        emit Borrow(msgSender, msgSender, assets);

        return true;
    }

    function liquidate(address violator, address collateral) external callThroughEVC withChecks(_msgSenderForBorrow()) {
        address msgSender = _msgSenderForBorrow();

        uint256 repayAssets = _debtOf(violator);

        if (msgSender == violator) {
            revert SelfLiquidation();
        }

        if (repayAssets == 0) {
            revert RepayAssetsInsufficient();
        }

        if (evc.isAccountStatusCheckDeferred(violator)) {
            revert ViolatorStatusCheckDeferred();
        }

        if (!evc.isControllerEnabled(violator, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        uint256 seizeShares = _calculateSharesToSeize(violator, collateral, repayAssets);

        _decreaseOwed(violator, repayAssets);
        _increaseOwed(msgSender, repayAssets);

        emit Repay(msgSender, violator, repayAssets);
        emit Borrow(msgSender, msgSender, repayAssets);

        if (collateral == address(this)) {
            if (!evc.isCollateralEnabled(violator, collateral)) {
                revert CollateralDisabled();
            }

            IERC20 _asset = ERC20(asset());

            _asset.transferFrom(violator, msgSender, seizeShares);

        } else {
            liquidateCollateralShares(collateral, violator, msgSender, seizeShares);
            evc.forgiveAccountStatusCheck(violator);
        }

    }

    function liquidateCollateralShares(
        address vault,
        address liquidated,
        address liquidator,
        uint256 shares
    ) internal {

        bytes memory result =
            evc.controlCollateral(vault, liquidated, 0, abi.encodeCall(ERC20(asset()).transfer, (liquidator, shares)));

        if (!(result.length == 0 || abi.decode(result, (bool)))) {
            revert SharesSeizureFailed();
        }
    }

    function _calculateLiabilityAndCollateral(
        address account,
        address[] memory collaterals
    ) internal returns (uint256 liabilityAssets, uint256 liabilityValue, uint256 collateralValue) {
        uint160 sqrtPriceX96After;
        uint32 initializedTicksCrossed;
        uint256 gasEstimate;
        uint256 temp;
        
        liabilityAssets = _debtOf(account);

        IQuoterV2.QuoteExactInputSingleParams memory params =  IQuoterV2.QuoteExactInputSingleParams(address(asset()), address(referenceAsset), liabilityAssets, uint24(3000), uint160(Math.sqrt(1e18 * (1 + 1e16))));

        (liabilityValue, sqrtPriceX96After, initializedTicksCrossed, gasEstimate) = IQuoterV2(oracle).quoteExactInputSingle(params);

        for (uint256 i = 0; i < collaterals.length; ++i) {
            ERC4626 collateral = ERC4626(collaterals[i]);
            uint256 cf = collateralFactor[collateral];

            if (cf != 0) {
                uint256 collateralShares = collateral.balanceOf(account);

                if (collateralShares > 0) {
                    uint256 collateralAssets = collateral.convertToAssets(collateralShares);

                    params = IQuoterV2.QuoteExactInputSingleParams(address(collateral.asset()), address(referenceAsset), collateralAssets, 3000, uint160(Math.sqrt(1e18 * (1 + 1e16))));

                    (temp, sqrtPriceX96After, initializedTicksCrossed, gasEstimate) = IQuoterV2(oracle).quoteExactInputSingle(params);

                    collateralValue += (
                        temp * cf
                    ) / COLLATERAL_FACTOR_SCALE;
                }
            }
        }
    }

    function _calculateSharesToSeize(
        address violator,
        address collateral,
        uint256 repayAssets
    ) internal returns (uint256) {

        uint256 repayValue;
        uint256 temp;

        uint256 cf = collateralFactor[ERC4626(collateral)];
        if (cf == 0) {
            revert CollateralDisabled();
        }

        (uint256 liabilityAssets, uint256 liabilityValue, uint256 collateralValue) =
            _calculateLiabilityAndCollateral(violator, getCollaterals(violator));

        if (repayAssets > liabilityAssets) {
            revert RepayAssetsExceeded();
        }

        if (collateralValue >= liabilityValue) {
            revert NoLiquidationOpportunity();
        }

        uint256 liquidationIncentive = 100 - (100 * collateralValue) / liabilityValue;

        if (liquidationIncentive > MAX_LIQUIDATION_INCENTIVE) {
            liquidationIncentive = MAX_LIQUIDATION_INCENTIVE;
        }

        uint256 maxRepayValue = (TARGET_HEALTH_FACTOR * liabilityValue - 100 * collateralValue)
            / (TARGET_HEALTH_FACTOR - (cf * (100 + liquidationIncentive)) / 100);

        repayValue = callOracle(address(asset()), address(referenceAsset), repayAssets);
        
        if (repayValue > maxRepayValue && maxRepayValue < liabilityValue / 2) {
            revert RepayAssetsExceeded();
        }

        address collateralAsset = address(ERC4626(collateral).asset());
        uint256 collateralUnit = 10 ** ERC20(collateralAsset).decimals();

        uint256 seizeValue = (repayValue * (100 + liquidationIncentive)) / 100;
        
        temp = callOracle(address(collateralAsset), address(referenceAsset), collateralUnit);
        uint256 seizeAssets = (seizeValue * collateralUnit)
            / temp;

        uint256 seizeShares = ERC4626(collateral).convertToShares(seizeAssets);

        if (seizeShares == 0) {
            revert RepayAssetsInsufficient();
        }
    
        return seizeShares;
    }

    function _debtOf(address borrower) public view returns (uint256) {

        uint256 currentInterestAccumulator;
        uint256 newTotalBorrowed;
        bool updated;
        
        uint256 debt = owed[borrower];

        if (debt == 0) return 0;

        (newTotalBorrowed, currentInterestAccumulator, updated) = _accrueInterestCalculate();
        return (debt * currentInterestAccumulator) / userInterestAccumulator[borrower];
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, false);
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, false);
    }

    function _updateInterest() internal virtual {
        uint256 borrowed = totalBorrowed;
        uint256 poolAssets = _totalAssets + borrowed;

        uint32 utilisation;
        if (poolAssets != 0) {
            utilisation = uint32((borrowed * type(uint32).max) / poolAssets);
        }

        interestRate = uint96(BASE_INTEREST_RATE + (utilisation * (MAX_INTEREST_RATE - BASE_INTEREST_RATE)) / type(uint32).max);

    }

    function _accrueInterest() internal virtual returns (uint256, uint256) {
        (uint256 currentTotalBorrowed, uint256 currentInterestAccumulator, bool shouldUpdate) =
            _accrueInterestCalculate();

        if (shouldUpdate == true) {
            totalBorrowed = currentTotalBorrowed;
            interestAccumulator = currentInterestAccumulator;
            lastInterestUpdate = block.timestamp;
        }

        return (currentTotalBorrowed, currentInterestAccumulator);
    }

    function _accrueInterestCalculate() internal view virtual returns (uint256, uint256, bool) {
        uint256 timeElapsed = block.timestamp - lastInterestUpdate;
        uint256 oldTotalBorrowed = totalBorrowed;
        uint256 oldInterestAccumulator = interestAccumulator;

        if (timeElapsed == 0) {
            return (oldTotalBorrowed, oldInterestAccumulator, false);
        }

        uint256 newInterestAccumulator =
            (FixedPointMathLib.rpow(uint256(interestRate) + ONE, timeElapsed, ONE) * oldInterestAccumulator * 100) / ONE;


        uint256 newTotalBorrowed = (oldTotalBorrowed * newInterestAccumulator) / oldInterestAccumulator;

        return (newTotalBorrowed, newInterestAccumulator, true);
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        uint256 totalSupply = totalSupply();

        return roundUp
            ? assets.mulDiv(totalSupply + 1, _totalAssets + currentTotalBorrowed + 1, Math.Rounding.Ceil)
            : assets.mulDiv(totalSupply + 1, _totalAssets + currentTotalBorrowed + 1, Math.Rounding.Floor);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        (uint256 currentTotalBorrowed,,) = _accrueInterestCalculate();

        uint256 totalSupply = totalSupply();

        return roundUp
            ? shares.mulDiv(_totalAssets + currentTotalBorrowed + 1, totalSupply + 1, Math.Rounding.Ceil)
            : shares.mulDiv(_totalAssets + currentTotalBorrowed + 1, totalSupply + 1, Math.Rounding.Floor);
    }

    function getAccountOwner(address account) internal view returns (address owner_out) {
        try evc.getAccountOwner(account) returns (address _owner) {
            owner_out = _owner;
        } catch {
            owner_out = account;
        }
    }

    function getCollateralFactor(ERC4626 vault) external view returns (uint256) {
        return collateralFactor[vault];
    }

    function getCollaterals(address account) internal view returns (address[] memory) {
        return evc.getCollaterals(account);
    }

    function getInterestRate() external view returns (uint256) {
        if (evc.isVaultStatusCheckDeferred(address(this))) {
            revert VaultStatusCheckDeferred();
        }

        return interestRate;
    }

    function callOracle(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amt) {
        uint256 outValue;
        uint160 sqrtPriceX96After;
        uint32 initializedTicksCrossed;
        uint256 gasEstimate;

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams(tokenIn, tokenOut, amountIn, 3000, uint160(Math.sqrt(1e18 * (1 + 1e16))));
        
        (outValue, sqrtPriceX96After, initializedTicksCrossed, gasEstimate) = IQuoterV2(oracle).quoteExactInputSingle(params);

        return outValue;
    }
}
