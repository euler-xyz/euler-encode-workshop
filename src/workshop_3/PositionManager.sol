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
    uint256 public constant RESERVE_RATIO = 20; // 20%

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

        VaultRegularBorrowable[2] memory topVaults;
        uint256[2] memory topInterestRates;

        for (uint256 i = 0; i < vaultCount; i++) {
            VaultRegularBorrowable currVault = VaultRegularBorrowable(vaults[i]);
            uint256 currInterest = uint256(currVault.getInterestRate());

            if (currInterest > topInterestRates[0]) {
                topInterestRates[1] = topInterestRates[0];
                topVaults[1] = topVaults[0];

                topInterestRates[0] = currInterest;
                topVaults[0] = currVault;
            } else if (currInterest > topInterestRates[1]) {
                topInterestRates[1] = currInterest;
                topVaults[1] = currVault;
            }
        }

        uint256 totalAmount = 0;
        uint256 reserveAmount;

        for (uint256 i = 0; i < vaultCount; i++) {
            uint256 vaultBal = VaultRegularBorrowable(vaults[i]).maxWithdraw(owner());

            if (vaultBal > 0) {
                if (i == 0) {
                    // Calculate reserve amount (20% of the total)
                    reserveAmount = (vaultBal * RESERVE_RATIO) / 100;
                    totalAmount += vaultBal - reserveAmount;
                } else {
                    totalAmount += vaultBal;
                }

                evc.call(
                    vaults[i],
                    owner(),
                    0,
                    abi.encodeWithSelector(VaultSimple.withdraw.selector, vaultBal, address(this), owner())
                );
            }
        }

        lastPositionUpdate = block.timestamp;

        // Deposit in top two vaults in 1:1 ratio
        uint256 depositAmount = totalAmount / 2;

        for (uint256 i = 0; i < 2; i++) {
            evc.call(
                address(topVaults[i]),
                owner(),
                depositAmount,
                abi.encodeWithSelector(VaultSimple.deposit.selector, depositAmount, owner())
            );
        }

        // Transfer reserved amount to owner
        if (reserveAmount > 0) {
            ERC20(topVaults[0].asset()).safeTransfer(owner(), reserveAmount);
        }
    }
}