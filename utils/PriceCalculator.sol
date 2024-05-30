// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {AggregatorV3Interface} from "../src/interfaces/IChainlinkAggregatorV3.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPriceCalculator} from "../src/interfaces/IPriceCalculator.sol";
import {VaultifyErrors} from "../src/libraries/VaultifyErrors.sol";
import {VaultifyStructs} from "../src/libraries/VaultifyStructs.sol";

contract PriceCalculator is IPriceCalculator {
    bytes32 private immutable NATIVE;

    // price Oracle Stale Threshold;
    uint256 public maxAge;

    AggregatorV3Interface public euroUsdFeed;

    constructor(bytes32 _native, address _euroUsdFeed) {
        NATIVE = _native;
        euroUsdFeed = AggregatorV3Interface(_euroUsdFeed);
    }

    // Exchange forloops for other solutions like structs
    function tokenToEuro(
        VaultifyStructs.Token memory _token,
        uint256 _tokenValue
    ) external view returns (uint256) {
        // Scale the _tokenValue based on the address of the token used
        uint256 collateralUSD;

        {
            uint256 collateralScaled = _tokenValue *
                10 ** getTokenScaleDiff(_token.symbol, _token.addr);

            // Get the price of the TokenToEuro from oracle price Fees;
            AggregatorV3Interface tokenToEuroFeed = AggregatorV3Interface(
                _token.clAddr
            );

            // Retieves the price of token in USD
            (
                ,
                int256 tokenUsdPrice,
                uint256 tokenUpdatedAt,
                ,

            ) = tokenToEuroFeed.latestRoundData();

            if (tokenUsdPrice <= 0) revert VaultifyErrors.InvalidPrice();

            if (block.timestamp - tokenUpdatedAt < maxAge) {
                revert VaultifyErrors.PriceStale();
            }

            // Calculates the collateral value in USD
            collateralUSD = collateralScaled * uint256(tokenUsdPrice);
        }

        // retrives the price of euroUSD
        (, int256 euroUsdPrice, uint256 euroUpdatedAt, , ) = euroUsdFeed
            .latestRoundData();

        if (euroUsdPrice <= 0) revert VaultifyErrors.InvalidPrice();

        if (block.timestamp - euroUpdatedAt < maxAge) {
            revert VaultifyErrors.PriceStale();
        }

        // Divide the price of the token/collateral by the EUROUSD value to which will give us the price of token in EURO
        return collateralUSD / uint256(euroUsdPrice);
    }

    function tokenToEuroAvg(
        VaultifyStructs.Token memory _token,
        uint256 _tokenValue
    ) external view returns (uint256) {
        uint256 collateralUSD;

        {
            uint256 collateralScaled = _tokenValue *
                10 ** getTokenScaleDiff(_token.symbol, _token.addr);

            // Get the price of the TokenToEuro from oracle price Fees;
            AggregatorV3Interface tokenToEuroFeed = AggregatorV3Interface(
                _token.clAddr
            );

            // Calculates the collateral value in USD
            collateralUSD = collateralScaled * getPriceAvg(tokenToEuroFeed, 4);
        }

        // retrives the price of euroUSD
        (, int256 euroUsdPrice, uint256 euroUpdatedAt, , ) = euroUsdFeed
            .latestRoundData();

        if (euroUsdPrice <= 0) revert VaultifyErrors.InvalidPrice();

        if (block.timestamp - euroUpdatedAt < maxAge) {
            revert VaultifyErrors.PriceStale();
        }

        return collateralUSD / uint256(euroUsdPrice);
    }

    function getTokenScaleDiff(
        bytes32 symbol,
        address tokenAddress
    ) private returns (uint256 scaleDiff) {
        return symbol == NATIVE ? 0 : 18 - ERC20(tokenAddress).decimals();
    }

    function euroToToken(
        VaultifyStructs.Token memory _token,
        uint256 _euroValue
    ) external view returns (uint256) {
        // Get the price of the TokenToEuro from oracle price Fees;
        AggregatorV3Interface tokenToEuroFeed = AggregatorV3Interface(
            _token.clAddr
        );

        // Retieves the price of token in USD
        (, int256 tokenUsdPrice, uint256 tokenUpdatedAt, , ) = tokenToEuroFeed
            .latestRoundData();

        // Check tokenToEuro price freshness
        if (tokenUsdPrice <= 0) revert VaultifyErrors.InvalidPrice();

        if (block.timestamp - tokenUpdatedAt < maxAge) {
            revert VaultifyErrors.PriceStale();
        }

        (, int256 euroUsdPrice, uint256 euroUpdatedAt, , ) = euroUsdFeed
            .latestRoundData();

        // Check euroUsdFeed price freshness
        if (euroUsdPrice <= 0) revert VaultifyErrors.InvalidPrice();

        if (block.timestamp - euroUpdatedAt < maxAge) {
            revert VaultifyErrors.PriceStale();
        }

        return
            ((_euroValue * uint256(euroUsdPrice)) / uint256(tokenUsdPrice)) /
            10 ** getTokenScaleDiff(_token.symbol, _token.addr);
    }

    function getPriceAvg(
        AggregatorV3Interface _tokenFeed,
        uint8 _period
    ) private view returns (uint256) {
        uint80 roundId;
        int256 answer;
        uint256 lastPeriod;

        // 1- get the last round data token to calculate it price averag
        (roundId, answer, , lastPeriod, ) = _tokenFeed.latestRoundData();

        if (answer <= 0) revert VaultifyErrors.InvalidPrice();

        // 2- Get the start period from were I should start calculate the historical data
        uint256 startPeriod = block.timestamp - _period * 1 hours;

        // 3- create Two variables to keep track of the accumalation of the price as well as the rounds
        uint256 accumlatedRoundPrices = uint256(answer);
        uint256 roundCount = 1;

        while (lastPeriod > startPeriod && roundId > 1) {
            roundId--;
            try _tokenFeed.getRoundData(roundId) {
                // Get the roundData of the _tokenFeed based on the provided roundId
                (, answer, , lastPeriod, ) = _tokenFeed.getRoundData(roundId);
                accumlatedRoundPrices += uint256(answer);
                roundCount++;
            } catch {
                continue;
            }
        }

        return accumlatedRoundPrices / roundCount;
    }
}
