// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// import {AggregatorV3Interface} from "./../interfaces/IChainlinkAggregatorV3.sol";
import {AggregatorV3InterfaceMock} from "../mocks/AggregatorV3InterfaceMock.sol";

contract ChainlinkMockForTest is AggregatorV3InterfaceMock {
    string private desc;

    PriceRound[] private prices;

    struct PriceRound {
        uint256 timestamp;
        int256 price;
    }

    constructor(string memory _desc) {
        desc = _desc;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function addPriceRound(uint256 timestamp, int256 price) external {
        prices.push(PriceRound(timestamp, price));
    }

    function setPrice(int256 _price) public {
        while (prices.length > 0) prices.pop();
        prices.push(PriceRound(block.timestamp - 4 hours, _price));
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        )
    {
        roundId = _roundId;
        answer = prices[roundId].price;
        updatedAt = prices[roundId].timestamp;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        )
    {
        roundId = uint80(prices.length - 1);
        answer = prices[roundId].price;
        updatedAt = prices[roundId].timestamp;
    }

    function description() external view returns (string memory) {
        return desc;
    }

    function version() external view returns (uint256) {
        return 1;
    }
}
