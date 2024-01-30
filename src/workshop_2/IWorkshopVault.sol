// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc/interfaces/IVault.sol";

interface IWorkshopVault is IVault {
    // [ASSIGNMENT]: add borrowing functionality by implementing the following functions:
    function borrow(uint256 assets, address receiver) external;
    function repay(uint256 assets, address receiver) external;
    function pullDebt(address from, uint256 assets) external returns (bool);
    // function liquidate(address violator, address collateral) external;

    function disableController() external;
    function checkAccountStatus(address account, address[] calldata collaterals) external returns (bytes4 magicValue);
    function maxWithdraw(address owner) view external returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    // [ASSIGNMENT]: - _convertToShares()
    // [ASSIGNMENT]: - _convertToAssets()

    // [ASSIGNMENT]: don't forget about implementing and using modified version of the _msgSender() function for the
    // borrowing purposes

    // [ASSIGNMENT] optional: add interest accrual
    // [ASSIGNMENT] optional: integrate with an oracle of choice in checkAccountStatus() and liquidate()
    // [ASSIGNMENT] optional: implement a circuit breaker in checkVaultStatus(), may be EIP-7265 inspired
    // [ASSIGNMENT] optional: add EIP-7540 compatibility for RWAs
}
