// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

interface IPOracle {
    function fetchQuote(uint256 tradeAmount, address sourceAsset, address targetAsset) external view returns (uint256 receivedAmount);
    function fetchQuotes(
        uint256 tradeAmount,
        address sourceAsset,
        address targetAsset
    ) external view returns (uint256 buyQuote, uint256 sellQuote);
}
