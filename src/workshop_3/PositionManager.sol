// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc-playground/vaults/VaultRegularBorrowable.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";

contract PositionManager {
    //a simple position manager that allows keepers to rebalance
    //assets between multiple vaults of user's choice using EVC authentication mechanism
    //and account owner's authorization
    IEVC internal evc;

    uint internal rebalanceTimeStamp;
    uint internal constant interval = 2 days;

    mapping(address => mapping(address => address[])) internal accountVaults;

    constructor() {
        rebalanceTimeStamp = block.timestamp;
    }

    //AN ACCOUNT OWNER MUST ADD AN OPERATOR OR OPERATORS TO OVERSEE ITS ASSETS ACCROSS VAULTS


    ////////////////an external function, anybody can add but sanity check is required///////////////////

    //@note for full implementation, an operator can manage multiple accounts
    function mustAddOperator(address operator, address[] calldata vaults)
        external
    {
        //@audit RE-ENTRANCY GUARD
        //set account operator
        require(operator != msg.sender, "you cannot set yourself as an operator");
        require(operator != address(0), "invalid operator");

        //@note for simplicity, acceptable vaults must be contract instances of VaultRegularBorrowable
        address[] memory vaultMemoryTransient = vaults;
        for (uint i = 0; i < vaultMemoryTransient.length; i++) {
            //sanity check
            require(
                VaultRegularBorrowable(vaultMemoryTransient[i])
                    .getInterestRate() > 0,
                "must be an instance of VaultRegular..."
            );
            address vault = vaultMemoryTransient[i];
            accountVaults[operator][msg.sender].push(vault);
        }
        //the account owner sets an operator
        evc.setAccountOperator(msg.sender, operator, true);
    }

    ///REBALANCE CAN ONLY BE CALLED 2 DAYS AFTER THE LAST CALL by the operator of the account

    function rebalanceOnMyWatch(address owner) external {
        //SANITY CHECK
        //Check if the operator is in charge of this account
        //Check if the operator is registered in this PositionManager contract
        address[] memory operatorExist = accountVaults[msg.sender][owner];
        //if empty, then operator does not exist
        require(operatorExist.length != 0, "No registered as operator");
        //Check the schedule call
        require(block.timestamp - rebalanceTimeStamp > interval, "wait!");
        uint lastHighestRate = 0;
        uint indexWithHighest;

        for (uint i = 0; i < operatorExist.length; i++) {
            //get interest rate

            address vault = operatorExist[i];
            uint interestRate = uint(VaultRegularBorrowable(vault).getInterestRate());
            if (interestRate > lastHighestRate) {
                lastHighestRate = interestRate;
                indexWithHighest = i;
            }
        }
        _rebalancingAction(
            operatorExist,
            owner,
            operatorExist[indexWithHighest]
        );

        rebalanceTimeStamp = block.timestamp;
    }

    function _rebalancingAction(
        address[] memory Vault,
        address owner,
        address theChosenVault
    ) internal {
        for (uint i = 0; i < Vault.length; i++) {
            if (Vault[i] != theChosenVault) {
                address vault = Vault[i];
                uint maxWithdrawValue = VaultRegularBorrowable(vault)
                    .maxWithdraw(owner);
                VaultRegularBorrowable(vault).withdraw(
                    maxWithdrawValue,
                    theChosenVault,
                    owner
                );
            }
        }
    }
}

