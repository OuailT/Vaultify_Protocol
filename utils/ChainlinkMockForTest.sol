// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "../src/mocks/AggregatorV3InterfaceMock.sol";

contract ChainlinkMockForTest is AggregatorV3Interface {
    string private desc;
    PriceRound[] private prices;

    struct PriceRound {
        uint256 timestamp;
        int256 price;
    }

    constructor(string memory _desc) {
        desc = _desc;
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function addPriceRound(uint256 timestamp, int256 price) external {
        prices.push(PriceRound(timestamp, price));
    }

    function setPrice(int256 _price) external {
        prices.push(PriceRound(block.timestamp, _price));
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        )
    {
        roundId = _roundId;
        require(roundId < prices.length, "Invalid roundId");
        answer = prices[roundId].price;
        updatedAt = prices[roundId].timestamp;
    }

    function latestRoundData()
        external
        view
        override
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

    function description() external view override returns (string memory) {
        return desc;
    }

    function version() external view override returns (uint256) {
        return 1;
    }
}
