// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "./IWorkshopVault.sol";

contract WorkshopVault is ERC4626 {
    IEVC internal immutable evc;

    constructor(IEVC _evc, IERC20 _asset, string memory _name, string memory _symbol)
        ERC4626(_asset)
        ERC20(_name, _symbol)
    {
        evc = _evc;
    }
}
