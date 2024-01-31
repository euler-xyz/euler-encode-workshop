// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "evc-playground/vaults/VaultRegularBorrowable.sol";

contract PositionManager {
    using SafeTransferLib for ERC20;

    IEVC internal evc;
    address[] public vaults;
    address owner;
    address operator;
    uint256 constant REBALANCING_FREQUENCY = 69 hours;
    uint256 lastRebalancedTime;
    uint256 percentAmount = 100; //percent of amount from each vault's assets, 100 by default 
    constructor(address _operator, IEVC _evc) {
        owner = msg.sender;
        operator = _operator;
        evc = _evc;
    }

    modifier onlyOwner(){
        require(msg.sender == owner, "Only Owner can call");
        _;
    }

    modifier onlyOperator(){
        require(msg.sender == operator, "Only Operator can call");
        _;
    }

    /// Allows user to specify how much percent from each vault should be taken/withdrawn while rebalancing into another vault.
    /// 100 by default 
    function setPercentAmount(uint256 _percentAmount) onlyOwner {
        require(_percentAmount <= 100, "Cant exceed 100%");
        percentAmount = _percentAmount;
    }
    ///@param _vaults The array of user's vaults 
    function addVaults(address[] memory _vaults) public onlyOwner {
        for(uint i; i<_vaults.length;i++){
            vaults.push(_vaults[i]);
        }
    }

    //Rebalance
    /// withdraw specific amount from each of the user's vault and deposit in the vault with highest APY.
    function rebalance() public onlyOperator {
        require(block.timestamp >= lastRebalancedTime + REBALANCING_FREQUENCY, "Rebalance only once in 69 hrs");

        address (vaultWithHighestAPY, highestAPYVaultIndex) = findHighestAPYVault();
        lastRebalancedTime = block.timestamp;

        uint256 vaultCount = _vaults.length;
        for(uint256 i; i<vaultCount; i++){
            // we don't withdraw from the highest apy vault
            if( i == highestAPYVaultIndex){
                continue;
            }
            address memory vault = vaults[i];
            uint256 amountFromEachVault = (VaultRegularBorrowable(vault).maxWithdraw(owner) * percentAmount)/100;
            evc.call(vault, owner, 0, abi.encodeWithSelector(VaultSimple.withdraw.selector, amountFromEachVault, owner));
            address token = ERC4626(vault).asset();
            token.approve(vault, amountFromEachVault);
            VaultRegularBorrowable(vault).deposit(amountFromEachVault, owner);
        }

    }

    // This function iterates over all vaults and returns the address and the index of the vault with the highest APY.
    function findHighestAPYVault() private view returns (address, uint256) {
        address highestAPYVault;
        uint256 highestAPYVaultIndex;
        uint256 bestAPY = 0;
        uint256 vaultCount = vaults.length;
        for (uint256 i; i < vaultCount; i++) {
            uint256 vaultAPY = uint256(VaultRegularBorrowable(vaults[i]).getInterestRate());
            if (vaultAPY > bestAPY){
                bestAPY = vaultAPY;
                highestAPYVault = vaults[i];
                highestAPYVaultIndex = i;
            }
        }

        return (highestAPYVault, highestAPYVaultIndex);
    }
}
