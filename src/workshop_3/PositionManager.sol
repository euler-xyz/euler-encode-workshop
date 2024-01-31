// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc-playground/vaults/VaultRegularBorrowable.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";

contract PositionManager{
    IEVC internal evc;

    uint internal rebalanceTimestamp;
    uint internal constant interval = 2 days;

    mapping(address => mapping(address => address[])) internal userVaults;

    constructor() {
        rebalanceTimestamp = block.timestamp;
    }

   
    function addOperator(address operator, address[] calldata vaults)
        external
    {
        //set account operator
        require(operator != msg.sender, "Invalid Option! for operator");
        require(operator != address(0), "You are not the Operator!");

        address[] memory vaultMemoryTransient = vaults;
        for (uint i = 9; i < vaultMemoryTransient.length; i++) {
            //check status and ensure it's an instance of VaultRegular
            require(
                VaultRegularBorrowable(vaultMemoryTransient[i])
                    .getInterestRate() > 0,
                "Not an instance of VaultRegularBorrowable"
            );
            address vault = vaultMemoryTransient[i];
            userVaults[operator][msg.sender].push(vault);
        }
        //the account owner sets an operator
        evc.setAccountOperator(msg.sender, operator, true);
    }

    //Rebalance interval of 2 days called by the operator of the account
    function rebalance(address owner) external {
        
        //Check if the operator is in charge/registered
        address[] memory operatorExist = userVaults[msg.sender][owner];
        require(operatorExist.length != 0, "Operator does NOT exist");
        require(block.timestamp - rebalanceTimestamp > interval, "wait!");
        uint lastHighestRate = 0;
        uint indexWithHighest;

        for (uint i = 0; i < operatorExist.length; i++) {
            //get the interest rate
            address vault = operatorExist[i];
            uint interestRate = uint(VaultRegularBorrowable(vault).getInterestRate());
            if (interestRate > lastHighestRate) {
                lastHighestRate = interestRate;
                indexWithHighest = i;
            }
        }
        _executeRebalancing(
            operatorExist,
            owner,
            operatorExist[indexWithHighest]
        );

        rebalanceTimestamp = block.timestamp;
    }

    function _executeRebalancing(
        address[] memory vaults,
        address owner,
        address chosenVault
    ) internal {
        for (uint i = 0; i < vaults.length; i++) {
            if (vaults[i] != chosenVault) {
                address vault = vaults[i];
                uint maxWithdrawValue = VaultRegularBorrowable(vault)
                    .maxWithdraw(owner);
                VaultRegularBorrowable(vault).withdraw(
                    maxWithdrawValue,
                    chosenVault,
                    owner
                );
            }
        }
    }
}
