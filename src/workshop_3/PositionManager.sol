// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import "evc-playground/vaults/VaultRegularBorrowable.sol";
import "evc-playground/vaults/VaultSimple.sol";
import "solmate/utils/SafeTransferLib.sol";
import "forge-std/console2.sol";

contract PositionManager {
    using SafeTransferLib for ERC20;

    IEVC public immutable evc;
    mapping(address => bool) public vaults;
    mapping(address => uint256) public lastRebalanceTimestamp;

    constructor(IEVC _evc, address[] memory _vaults) {
        evc = _evc;
        for (uint256 i = 0; i < _vaults.length; i += 1) {
            vaults[_vaults[i]] = true;
        }
    }

    function rebalance(address _onBehalfOfAccount, address _currentVault, address _newVault) public {
        require(
            lastRebalanceTimestamp[_onBehalfOfAccount] == 0
                || block.timestamp >= lastRebalanceTimestamp[_onBehalfOfAccount] + 1 days,
            "Rebalance can only be performed once a day"
        );
        require(vaults[_newVault], "Not allowed vault");
        require(
            VaultRegularBorrowable(_newVault).getInterestRate()
                > VaultRegularBorrowable(_currentVault).getInterestRate(),
            "Cannot rebalance to a lowest rate vault"
        );

        ERC20 asset = ERC4626(_currentVault).asset();
        uint256 assets = VaultRegularBorrowable(_currentVault).maxWithdraw(_onBehalfOfAccount);

        // if there's anything to withdraw, withdraw it to this contract
        evc.call(
            _currentVault,
            _onBehalfOfAccount,
            0,
            abi.encodeWithSelector(VaultSimple.withdraw.selector, assets, address(this), _onBehalfOfAccount)
        );

        // transfer 1% of the withdrawn assets as a tip to the msg.sender
        asset.safeTransfer(msg.sender, assets / 100);

        // rebalance the rest on behalf of account
        asset.approve(_newVault, ERC20(asset).balanceOf(address(this)));
        VaultRegularBorrowable(_newVault).deposit(ERC20(asset).balanceOf(address(this)), _onBehalfOfAccount);

        // Update the last rebalance timestamp
        lastRebalanceTimestamp[_onBehalfOfAccount] = block.timestamp;
    }
}
