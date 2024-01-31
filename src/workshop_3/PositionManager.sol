// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc-playground/vaults/VaultRegularBorrowable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract PositionManager is AccessControl {
    using SafeTransferLib for ERC20;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    struct Vault {
        address vault;
        uint256 apy;
    }

    IEVC internal evc;
    Vault[] public vaults;
    mapping(address => uint256) public userBalance;
    mapping(address => uint256) public lastRebalanced;

    constructor(address _keeper, IEVC _evc) {
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(KEEPER_ROLE, _keeper);
        evc = _evc;
    }

    // Only accounts with the DEFAULT_ADMIN_ROLE can add new vaults
    // This function allows adding new vaults to the system.
    function addVault(address vault) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 apy = uint256(VaultRegularBorrowable(vault).getInterestRate());
        vaults.push(Vault({vault: vault, apy: apy}));
    }

    // Only accounts with the KEEPER_ROLE can call the rebalance function
    // This function allows keepers to rebalance their assets.
    // Before doing so, it checks that at least one day has passed since the last rebalance.
    // It then finds the vault with the highest APY and transfers the assets to that vault.
    function rebalance(address _oldVault, address _user) public onlyRole(KEEPER_ROLE) {
        require(block.timestamp >= lastRebalanced[_user] + 1 days, "Cannot rebalance more than once per day");

        uint256 bestVaultIndex = findBestVault();
        Vault storage bestVault = vaults[bestVaultIndex];

        // The vault with the highest APY
        address _vault = bestVault.vault;

        // The asset token of old vault
        ERC20 token = ERC4626(_oldVault).asset();

        // Allowed amount for tranfer
        uint256 amount = VaultRegularBorrowable(_oldVault).maxWithdraw(_user);
        userBalance[_user] = amount;

        // Withdraw from old vault to Position manager
        evc.call(address(_oldVault), _user, 0, abi.encodeWithSelector(VaultSimple.withdraw.selector, amount, _user));

        // Approve token for rebalancing
        token.approve(_vault, userBalance[_user]);
        // Deposits a certain amount of assets for a receiver to the highest APY vault
        VaultRegularBorrowable(_vault).deposit(userBalance[_user], _user);

        lastRebalanced[_user] = block.timestamp;
    }

    // This function iterates over all vaults and returns the index of the vault with the highest APY.
    function findBestVault() private view returns (uint256) {
        uint256 bestVaultIndex = 0;
        uint256 bestApy = 0;

        // Update the apy of all stored vaults
        for (uint256 i = 0; i < vaults.length; i++) {
            Vault memory vault = vaults[i];
            vault.apy = uint256(VaultRegularBorrowable(vault.vault).getInterestRate());
        }

        for (uint256 i = 0; i < vaults.length; i++) {
            Vault memory vault = vaults[i];

            if (vault.apy > bestApy) {
                bestVaultIndex = i;
                bestApy = vault.apy;
            }
        }

        return bestVaultIndex;
    }
}
