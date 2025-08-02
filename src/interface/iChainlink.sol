// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Chainlink interfaces
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

interface AggregatorV2V3Interface is AggregatorV3Interface {
    function description() external view returns (string memory);
}
