// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc/interfaces/IVault.sol";

contract WorkshopVault is IVault {
    mapping(address => uint256) private userBalances;
    mapping(address => uint256) private userDebts;
    uint256 private totalAvailableAssets;
    uint256 private totalAvailableShares;
    bool private isControllerActive = true;
    address private lastBorrowingUser;

    function borrow(uint256 requestedAssets, address borrower) external override {
        require(isControllerActive, "Controller is disabled");
        require(totalAvailableAssets >= requestedAssets, "Insufficient assets in the system");
        totalAvailableAssets -= requestedAssets;
        userDebts[borrower] += requestedAssets;
        lastBorrowingUser = borrower;
    }

    function repay(uint256 repaymentAmount, address debtor) external override {
        require(isControllerActive, "Controller is disabled");
        require(userDebts[debtor] >= repaymentAmount, "Insufficient debt to repay");
        require(userBalances[debtor] >= repaymentAmount, "Insufficient balance to repay");
        totalAvailableAssets += repaymentAmount;
        userDebts[debtor] -= repaymentAmount;
        userBalances[debtor] -= repaymentAmount;
    }

    function pullDebt(address debtor, uint256 debtAmount) external override returns (bool) {
        require(isControllerActive, "Controller is disabled");
        require(userDebts[debtor] >= debtAmount, "Insufficient debt to pull");
        userDebts[debtor] -= debtAmount;
        return true;
    }

    function liquidate(address insolventAccount) external override {
        require(isControllerActive, "Controller is disabled");
        require(userDebts[insolventAccount] > 0, "No debt to liquidate");
        totalAvailableAssets += userDebts[insolventAccount];
        userDebts[insolventAccount] = 0;
    }

    function disableController() external {
        require(msg.sender == owner(), "Only owner can disable the controller");
        // Disable the controller
        isControllerActive = false;
    }

    function checkAccountStatus() external view override {
        if (userBalances[msg.sender] < userDebts[msg.sender]) {
            // The account is underfunded
        } else {
            // The account is in good standing
        }
    }

    function maxWithdraw() external view override returns (uint256) {
        // Calculate the maximum withdrawal amount
        uint256 maxWithdrawalAmount = userBalances[msg.sender] - userDebts[msg.sender];
        return maxWithdrawalAmount;
    }

    function maxRedeem() external view override returns (uint256) {
        // Calculate the maximum redemption amount
        uint256 maxRedemptionAmount = userBalances[msg.sender] - userDebts[msg.sender];
        return maxRedemptionAmount;
    }

    function _convertToShares(uint256 assetAmount) internal view returns (uint256) {
        require(totalAvailableAssets > 0 && totalAvailableShares > 0, "Cannot convert to shares");
        return (assetAmount * totalAvailableShares) / totalAvailableAssets;
    }

    function _convertToAssets(uint256 shareAmount) internal view returns (uint256) {
        require(totalAvailableAssets > 0 && totalAvailableShares > 0, "Cannot convert to assets");
        return (shareAmount * totalAvailableAssets) / totalAvailableShares;
    }

    function _msgSender() internal view override returns (address) {
        // Return the last borrowing user for borrowing purposes
        return lastBorrowingUser;
    }
}
