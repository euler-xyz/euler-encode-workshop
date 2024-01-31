// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "./IPriceOracle.sol";
import "./WorkshopVault.sol";

/// @title VaultRegularBorrowable
/// @notice This contract extends VaultSimpleBorrowable with additional features like interest rate accrual and
/// recognition of external collateral vaults.
contract VaultRegularBorrowable is WorkshopVault {
    uint256 internal constant COLLATERAL_FACTOR_SCALE = 100;
    uint256 internal constant MAX_LIQUIDATION_INCENTIVE = 20;
    uint256 internal constant TARGET_HEALTH_FACTOR = 125;
    uint256 internal constant HARD_LIQUIDATION_THRESHOLD = 1;

    // oracle
    ERC20 public referenceAsset;
    IPriceOracle public oracle;

    error NoLiquidationOpportunity();
    error RepayAssetsInsufficient();
    error RepayAssetsExceeded();
    error ViolatorStatusCheckDeferred();
    error InvalidCollateralFactor();
    error SharesSeizureFailed();

    constructor(
        IEVC _evc,
        ERC20 _asset,
        IPriceOracle _oracle,
        ERC20 _referenceAsset,
        string memory _name,
        string memory _symbol
    ) WorkshopVault(_evc, _asset, _name, _symbol) {
        oracle = _oracle;
        referenceAsset = _referenceAsset;
        lastInterestUpdate = block.timestamp;
        interestAccumulator = ONE;
    }

    function checkAccountStatus(
        address account,
        address[] calldata collaterals
    ) public virtual override returns (bytes4 magicValue) {
        require(msg.sender == address(evc), "only evc can call this");
        require(evc.areChecksInProgress(), "can only be called when checks in progress");

        // some custom logic evaluating the account health
        if (debtOf(account) > 0) {
            (, uint256 liabilityValue, uint256 collateralValue) = _calculateLiabilityAndCollateral(account, collaterals);

            if (liabilityValue > collateralValue) {
                revert AccountUnhealthy();
            }
        }

        return IVault.checkAccountStatus.selector;
    }

    function liquidate(
        address violator,
        address collateral,
        uint256 repayAssets
    ) external callThroughEVC nonReentrant withChecks(_msgSenderForBorrow()) {
        address msgSender = _msgSenderForBorrow();

        if (msgSender == violator) {
            revert SelfLiquidation();
        }

        // sanity check: the violator must be under control of the EVC
        if (!evc.isControllerEnabled(violator, address(this))) {
            revert ControllerDisabled();
        }

        // do not allow to seize the assets for collateral without a collateral factor.
        // note that a user can enable any address as collateral, even if it's not recognized
        // as such (cf == 0)
        uint256 cf = collateralFactor[ERC4626(collateral)];
        if (cf == 0) {
            revert CollateralDisabled();
        }

        takeVaultSnapshot();

        uint256 seizeShares;
        {
            (uint256 liabilityAssets, uint256 liabilityValue, uint256 collateralValue) =
                _calculateLiabilityAndCollateral(violator, evc.getCollaterals(violator));

            // trying to repay more than the violator owes
            if (repayAssets > liabilityAssets) {
                revert RepayAssetsExceeded();
            }

            // check if violator's account is unhealthy
            if (collateralValue >= liabilityValue) {
                revert NoLiquidationOpportunity();
            }

            // calculate dynamic liquidation incentive
            uint256 liquidationIncentive = 100 - (100 * collateralValue) / liabilityValue;

            if (liquidationIncentive > MAX_LIQUIDATION_INCENTIVE) {
                liquidationIncentive = MAX_LIQUIDATION_INCENTIVE;
            }

            // calculate the max repay value that will bring the violator back to target health factor
            uint256 maxRepayValue = (TARGET_HEALTH_FACTOR * liabilityValue - 100 * collateralValue)
                / (TARGET_HEALTH_FACTOR - (cf * (100 + liquidationIncentive)) / 100);

            // get the desired value of repay assets
            uint256 repayValue =
                IPriceOracle(oracle).getQuote(repayAssets, address(ERC20(asset())), address(referenceAsset));

            // check if the liquidator is not trying to repay too much.
            if (
                repayValue > maxRepayValue && repayAssets > HARD_LIQUIDATION_THRESHOLD * 10 ** ERC20(asset()).decimals()
            ) {
                revert RepayAssetsExceeded();
            }

            address collateralAsset = address(ERC4626(collateral).asset());
            uint256 one = 10 ** ERC20(collateralAsset).decimals();

            uint256 seizeValue = (repayValue * (100 + liquidationIncentive)) / 100;

            uint256 seizeAssets =
                (seizeValue * one) / IPriceOracle(oracle).getQuote(one, collateralAsset, address(referenceAsset));

            seizeShares = ERC4626(collateral).convertToShares(seizeAssets);

            if (seizeShares == 0) {
                revert RepayAssetsInsufficient();
            }
        }

        _decreaseOwed(violator, repayAssets);
        _increaseOwed(msgSender, repayAssets);

        emit Repay(msgSender, violator, repayAssets);
        emit Borrow(msgSender, msgSender, repayAssets);

        if (collateral == address(this)) {
            // if the liquidator tries to seize the assets from this vault,
            // we need to be sure that the violator has enabled this vault as collateral
            if (!evc.isCollateralEnabled(violator, collateral)) {
                revert CollateralDisabled();
            }

            ERC20(asset()).transferFrom(violator, msgSender, seizeShares);
        } else {
            // Control the collateral in order to transfer shares from the violator's vault to the liquidator.
            bytes memory result = evc.controlCollateral(
                collateral, violator, 0, abi.encodeCall(ERC20(asset()).transfer, (msgSender, seizeShares))
            );

            if (!abi.decode(result, (bool))) {
                revert SharesSeizureFailed();
            }

            // Allow violator to have unhealthy state after the liquidation
            evc.forgiveAccountStatusCheck(violator);
        }
    }

    function _calculateLiabilityAndCollateral(
        address account,
        address[] memory collaterals
    ) internal view returns (uint256 liabilityAssets, uint256 liabilityValue, uint256 collateralValue) {
        liabilityAssets = debtOf(account);

        liabilityValue =
            IPriceOracle(oracle).getQuote(liabilityAssets, address(ERC20(asset())), address(referenceAsset));

        for (uint256 i = 0; i < collaterals.length; ++i) {
            ERC4626 collateral = ERC4626(collaterals[i]);
            uint256 cf = collateralFactor[collateral];

            if (cf != 0) {
                uint256 collateralShares = collateral.balanceOf(account);

                if (collateralShares > 0) {
                    uint256 collateralAssets = collateral.convertToAssets(collateralShares);

                    collateralValue += (
                        IPriceOracle(oracle).getQuote(
                            collateralAssets, address(collateral.asset()), address(referenceAsset)
                        ) * cf
                    ) / COLLATERAL_FACTOR_SCALE;
                }
            }
        }
    }
}
