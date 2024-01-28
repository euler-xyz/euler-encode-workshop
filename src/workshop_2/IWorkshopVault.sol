// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc/interfaces/IVault.sol";

contract IWorkshopVault is IVault {
    mapping(address => uint256) private balances;
    mapping(address => uint256) private debts;
    uint256 private totalAssets;
    uint256 private totalShares;
    bool private controllerEnabled = true;
    address private lastBorrower;

    function borrow(uint256 assets, address receiver) external override {
        require(controllerEnabled, "Controller is disabled");
        require(totalAssets >= assets, "Not enough assets in the contract");
        totalAssets -= assets;
        debts[receiver] += assets;
        lastBorrower = receiver;
    }

    function repay(uint256 assets, address receiver) external override {
        require(controllerEnabled, "Controller is disabled");
        require(debts[receiver] >= assets, "Not enough debt to repay");
        require(balances[receiver] >= assets, "Not enough balance to repay");
        totalAssets += assets;
        debts[receiver] -= assets;
        balances[receiver] -= assets;
    }

    function pullDebt(address from, uint256 assets) external override returns (bool) {
        require(controllerEnabled, "Controller is disabled");
        require(debts[from] >= assets, "Not enough debt to pull");
        debts[from] -= assets;
        return true;
    }

    function liquidate(address violator) external override {
        require(controllerEnabled, "Controller is disabled");
        require(debts[violator] > 0, "No debt to liquidate");
        totalAssets += debts[violator];
        debts[violator] = 0;
    }

    function disableController() external {
        require(msg.sender == owner(), "Only owner can disable the controller");
        // Disable the controller
        controllerEnabled = false;
    }

    function checkAccountStatus() external view override {
        if (balances[msg.sender] < debts[msg.sender]) {
            // The account is underfunded
        } else {
            // The account is in good standing
        }
    }

    function maxWithdraw() external view override returns (uint256) {
        // Determine the maximum withdrawal amount
        return balances[msg.sender] - debts[msg.sender];
    }

    function maxRedeem() external view override returns (uint256) {
        // Determine the maximum redeem amount
        return balances[msg.sender] - debts[msg.sender];
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        require(totalAssets > 0 && totalShares > 0, "Cannot convert to shares");
        return (assets * totalShares) / totalAssets;
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        require(totalAssets > 0 && totalShares > 0, "Cannot convert to assets");
        return (shares * totalAssets) / totalShares;
    }

    function _msgSender() internal view override returns (address) {
        // Return the last borrower for borrowing purposes
        return lastBorrower;
    }
}
