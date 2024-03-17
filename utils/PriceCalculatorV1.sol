// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol" as Chainlink;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "contracts/interfaces/IPriceCalculator.sol";

contract PriceCalculator is IPriceCalculator {
    bytes32 private immutable NATIVE;

    Chainlink.AggregatorV3Interface public immutable clEurUsd;

    constructor(bytes32 _native, address _clEurUsd) {
        NATIVE = _native;
        clEurUsd = Chainlink.AggregatorV3Interface(_clEurUsd);
    }

    function avgPrice(
        uint8 _hours,
        Chainlink.AggregatorV3Interface _priceFeed
    ) private view returns (uint256) {
        uint256 startPeriod = block.timestamp - _hours * 1 hours;
        uint256 roundTS;
        uint80 roundId;
        int256 answer;
        (roundId, answer, , roundTS, ) = _priceFeed.latestRoundData();
        uint256 accummulatedRoundPrices = uint256(answer);
        uint256 roundCount = 1;
        while (roundTS > startPeriod && roundId > 1) {
            roundId--;
            try _priceFeed.getRoundData(roundId) {
                (, answer, , roundTS, ) = _priceFeed.getRoundData(roundId);
                accummulatedRoundPrices += uint256(answer);
                roundCount++;
            } catch {
                continue;
            }
        }
        return accummulatedRoundPrices / roundCount;
    }

    // To understand more later...
    function getTokenScaleDiff(
        bytes32 _symbol,
        address _tokenAddress
    ) private view returns (uint256 scaleDiff) {
        return _symbol == NATIVE ? 0 : 18 - ERC20(_tokenAddress).decimals();
    }

    function tokenToEur(
        ITokenManager.Token memory _token, // WBTC
        uint256 _tokenValue // 100 WBTC
    ) external view returns (uint256) {
        // Retrieves the Chainlink price feed interface for the token's USD price
        Chainlink.AggregatorV3Interface tokenUsdClFeed = Chainlink
            .AggregatorV3Interface(_token.clAddr);

        // Scales the token value based on its symbol and address
        uint256 scaledCollateral = _tokenValue *
            10 ** getTokenScaleDiff(_token.symbol, _token.addr);

        // Retrieves the latest round data for the token's(WTBC) USD price
        (, int256 _tokenUsdPrice, , , ) = tokenUsdClFeed.latestRoundData();

        // Calculates the collateral value in USD
        uint256 collateralUsd = scaledCollateral * uint256(_tokenUsdPrice);

        // Retrieves the latest round data for the EUR/USD price feed
        (, int256 eurUsdPrice, , , ) = clEurUsd.latestRoundData();

        // Converts the collateral value from USD to EUR
        return collateralUsd / uint256(eurUsdPrice);
    }

    function eurToToken(
        ITokenManager.Token memory _token,
        uint256 _eurValue
    ) external view returns (uint256) {
        // Retrieves the Chainlink price feed interface for the token's USD price
        Chainlink.AggregatorV3Interface tokenUsdClFeed = Chainlink
            .AggregatorV3Interface(_token.clAddr);

        // Retrieves the latest round data for the token's USD price
        (, int256 tokenUsdPrice, , , ) = tokenUsdClFeed.latestRoundData();

        // Retrieves the latest round data for the EUR/USD price feed
        (, int256 eurUsdPrice, , , ) = clEurUsd.latestRoundData();
        return
            // Calculates the token value in EUR
            (_eurValue * uint256(eurUsdPrice)) /
            uint256(tokenUsdPrice) /
            10 ** getTokenScaleDiff(_token.symbol, _token.addr);
    }
}
