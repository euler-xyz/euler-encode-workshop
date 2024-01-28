// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "evc-playground/vaults/VaultRegularBorrowable.sol";

contract PositionManager is Ownable {
    // Mapping of vault addresses
    mapping(address => VaultRegularBorrowable) public vaults;
    
    // The last rebalance timestamp
    uint256 public lastRebalance;

    // Rebalance frequency in seconds (86400 for 24 hours)
    uint256 public rebalanceFrequency = 86400;

    // Events
    event VaultAdded(address indexed vault);
    event Rebalanced(address indexed vault);

    // Function to add a new vault
    function addVault(address vaultAddress) public onlyOwner {
        require(vaultAddress != address(0), "Invalid address");
        require(vaults[vaultAddress] == address(0), "Vault already added");

        vaults[vaultAddress] = VaultRegularBorrowable(vaultAddress);

        emit VaultAdded(vaultAddress);
    }

    // Function to rebalance assets
    function rebalance() public onlyOwner {
        require(block.timestamp >= lastRebalance + rebalanceFrequency, "Rebalance not allowed yet");

        VaultRegularBorrowable highestApyVault;
        uint256 highestApy = 0;

        // Find the vault with the highest APY
        for (uint256 i = 0; i < vaults.length; i++) {
            uint256 apy = vaults[i].getApy();
            if (apy > highestApy) {
                highestApy = apy;
                highestApyVault = vaults[i];
            }
        }

        // Deposit all assets into the vault with the highest APY
        highestApyVault.depositAll();

        // Update the last rebalance timestamp
        lastRebalance = block.timestamp;

        emit Rebalanced(address(highestApyVault));
    }
}
