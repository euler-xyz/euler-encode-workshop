// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "solmate/utils/SafeTransferLib.sol";
import "evc-playground/vaults/VaultRegularBorrowable.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PositionManager is Ownable {
    using SafeTransferLib for ERC20;

    IEVC public immutable evc;

    mapping(uint256 => address) public vaults;

    uint256 vaultCount;
    uint256 public lastPositionUpdate;
    uint256 public oneDay = 86400;

    constructor(IEVC _evc) Ownable(msg.sender) {
        evc = _evc;
        vaultCount = 0;
    }

    function addVault(address vaultAddress) public onlyOwner {
        require(vaultAddress != address(0), "Invalid address");
        vaults[vaultCount] = vaultAddress;
        vaultCount += 1;
    }

    function rebalance() public {
        require(block.timestamp >= lastPositionUpdate + oneDay, "Can only be performed once in 24 hours"); 

        VaultRegularBorrowable vaultInInterest;
        uint256 totalAmount = 0;
        uint256 highestInterest = 0;

        for (uint256 i = 0; i < vaultCount; i++) {
            VaultRegularBorrowable currVault = VaultRegularBorrowable(vaults[i]);
            uint256 currInterest = currVault.getInterestRate();
            if (currInterest > highestInterest) {
                highestInterest = currInterest;
                vaultInInterest = currVault;
            }
            uint256 vaultBal = currVault.maxWithdraw(owner());
            if(vaultBal > 0) {
                evc.call(
                    vaults[i],
                    owner(),
                    0,
                    abi.encodeWithSelector(VaultSimple.withdraw.selector, vaultBal, address(this), owner())
                );
                totalAmount += vaultBal;
            }
        }

        lastPositionUpdate = block.timestamp;

        if(totalAmount > 0) {
            evc.call(
                address(vaultInInterest), 
                owner(), 
                totalAmount, 
                abi.encodeWithSelector(VaultSimple.deposit.selector, totalAmount, owner())
            );
        }
    }
}