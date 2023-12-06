// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc/interfaces/IVault.sol";

interface IWorkshopVault is IVault {
    // [ASSIGNMENT]: add borrowing functionality by implementing the following functions:
    function borrow(uint256 assets, address receiver) external;
    function repay(uint256 assets, address receiver) external;
    function pullDebt(address from, uint256 assets) external returns (bool);
    function liquidate(address violator, address collateral) external;

    // [ASSIGNMENT]: don't forget that the following functions must be overridden in order to support borrowing:
    // [ASSIGNMENT]: - disableController()
    // [ASSIGNMENT]: - checkAccountStatus()
    // [ASSIGNMENT]: - maxWithdraw()
    // [ASSIGNMENT]: - maxRedeem()
    // [ASSIGNMENT]: - _convertToShares()
    // [ASSIGNMENT]: - _convertToAssets()

    // [ASSIGNMENT] optional: add interest accrual
    // [ASSIGNMENT] optional: integrate with an oracle of choice in checkAccountStatus() and liquidate()
    // [ASSIGNMENT] optional: implement a circuit breaker in checkVaultStatus(), may be EIP-7265 inspired
    // [ASSIGNMENT] optional: add EIP-7540 compatibility for RWAs
}
