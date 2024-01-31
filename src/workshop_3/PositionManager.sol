// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc-playground/vaults/VaultRegularBorrowable.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";

contract PositionManager {
    IEVC internal evc;

    uint internal lastRebalanceTime;
    uint internal constant rebalanceInterval = 1 days;

    struct UserVault {
        address operator;
        address[] vaults;
    }

    mapping(address => UserVault) internal userVaults;

    constructor(IEVC _evc) {
        evc = _evc;
        lastRebalanceTime = block.timestamp;
    }

    function addOperator(address operator, address[] calldata vaults) external {
        require(operator != msg.sender, "Operator not valid");
        require(operator != address(0), "Address invalid");

        for (uint i = 0; i < vaults.length; i++) {
            require(VaultRegularBorrowable(vaults[i]).getInterestRate() > 0, "Wrong vault");
            userVaults[msg.sender].vaults.push(vaults[i]);
        }

        userVaults[msg.sender].operator = operator;
        evc.setAccountOperator(msg.sender, operator, true);
    }

    function rebalance(address owner) external {
        require(userVaults[msg.sender].operator == msg.sender, "Action not allowed");
        require(block.timestamp - lastRebalanceTime > rebalanceInterval, "Wait for the rebalance interval");

        address[] memory vaults = userVaults[owner].vaults;
        uint highestInterestRate = 0;
        uint bestVaultIndex;

        for (uint i = 0; i < vaults.length; i++) {
            uint interestRate = VaultRegularBorrowable(vaults[i]).getInterestRate();
            if (interestRate > highestInterestRate) {
                highestInterestRate = interestRate;
                bestVaultIndex = i;
            }
        }

        _executeRebalancing(vaults, owner, vaults[bestVaultIndex]);
        lastRebalanceTime = block.timestamp;
    }

    function _executeRebalancing(address[] memory vaults, address owner, address bestVault) internal {
        for (uint i = 0; i < vaults.length; i++) {
            if (vaults[i] != bestVault) {
                uint maxWithdrawValue = VaultRegularBorrowable(vaults[i]).maxWithdraw(owner);
                VaultRegularBorrowable(vaults[i]).withdraw(maxWithdrawValue, bestVault, owner);
            }
        }
    }
}
