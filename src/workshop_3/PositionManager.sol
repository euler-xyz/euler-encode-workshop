// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc-playground/vaults/VaultRegularBorrowable.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";

contract PositionManager {
    ///implementing a position manager that considers APY for rebalancing,
    ///It only takes into consideration daily interest rates of the vaults as the
    ///relevant parameter
    mapping(address => mapping(address => address[])) public operatorVaults;
    uint lastRebalanceTimestamps;
    uint rebalanceIntervals = 1 days;

    //mapping of vault addresses(evc compatible vaults) to their interate rates

//////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////VAULTS MUST BE INSTANCES OF VAULT_REGULAR_BORROWABLE////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    function addVaultToManager(address owner, address[] memory vaultAddresses)
        external
    {
        for (uint i = 0; i < vaultAddresses.length; i++) {
            //Vault 4626 must be compatible with EVC
            address vaultAddr = vaultAddresses[i];

            require(
                IEVC(vaultAddr).getAccountOwner(owner) == owner,
                "non-EVC vault or owner not registered"
            );
            require(
                IEVC(vaultAddr).isAccountOperatorAuthorized(owner, msg.sender),
                "not an operator"
            );

            operatorVaults[msg.sender][owner].push(vaultAddr);
        }
    }

    //get the interest rates of the registered vaults, compare the interests and return the address of the highest
    //vaults
    function _getInterestRatesOfVaults(address accountOwner)
        internal
        view
        returns (address)
    {
        //msg.sender must be a registered operator in the Manager contract
        require(
            operatorVaults[msg.sender][accountOwner].length > 0,
            "error, add vault to manager"
        );
        address[] memory operatorVault = operatorVaults[msg.sender][
            accountOwner
        ];
        uint highestRate = 0;
        uint index;
        for (uint i = 0; i < operatorVault.length; i++) {
            //@audit CAUTION!!! CHECK NEEDED TO AVOID OVERFLOW, VAULTREGULARBORROWABLE CONTRACT
            //USING "INT256" AS RETURN TYPE FOR ::getInterestRate()
            uint interestRate = uint(
                VaultRegularBorrowable(operatorVault[i]).getInterestRate()
            );

            if (interestRate > highestRate) {
                highestRate = interestRate;
                index = i;
            }
        }
        return operatorVault[index];
    }

    function rebalancer(address accountOwner) external  {
        //msg.sender must be a registered operator in the Manager contract
        require(
            operatorVaults[msg.sender][accountOwner].length > 0,
            "error, add vault to manager"
        );
        require(
            (block.timestamp - lastRebalanceTimestamps) > rebalanceIntervals,
            "24 hours wait"
        );
        address vaultWithHighest = _getInterestRatesOfVaults(accountOwner);
        address[] memory operatorVault = operatorVaults[msg.sender][
            accountOwner
        ];
        for (uint i = 0; i < operatorVault.length; i++) {
            if (operatorVault[i] != vaultWithHighest) {
                address vaultOthers = operatorVault[i];
                uint max = VaultRegularBorrowable(vaultOthers).maxWithdraw(
                    accountOwner
                );

                /////CALL THROUGH EVC AS AN OPERATOR/////////////////////////
                VaultRegularBorrowable(vaultOthers).withdraw(
                    max,
                    vaultWithHighest,
                    accountOwner
                );
            }
        }
    }

   
}
