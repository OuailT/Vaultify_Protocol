// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

// import {AggregatorV3Interface} from "../src/interfaces/IChainlinkAggregatorV3.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Mock} from "../src/mocks/IERC20Mock.sol";
import {IPriceCalculator} from "../src/interfaces/IPriceCalculator.sol";
import {VaultifyErrors} from "../src/libraries/VaultifyErrors.sol";
import {VaultifyStructs} from "../src/libraries/VaultifyStructs.sol";
import {AggregatorV3InterfaceMock} from "src/mocks/AggregatorV3InterfaceMock.sol";

// Changes for test to work
// changed ERC20 with IERC20Mock()
// changed AggregatorV3Interface with import

contract PriceCalculator is IPriceCalculator {
    bytes32 private immutable NATIVE;

    // price Oracle Stale Threshold;
    uint256 public maxAge;

    AggregatorV3InterfaceMock public euroUsdFeed;

    constructor(bytes32 _native, address _euroUsdFeed) {
        NATIVE = _native;
        euroUsdFeed = AggregatorV3InterfaceMock(_euroUsdFeed);
    }

    // Exchange forloops for other solutions like structs
    function tokenToEuro(
        VaultifyStructs.Token memory _token,
        uint256 _tokenValue
    ) external view returns (uint256) {
        address tokenOracle = _token.clAddr;
        if (tokenOracle == address(0)) revert VaultifyErrors.ZeroAddress();
        // Get the price of the TokenToEuro from oracle price Fees;
        AggregatorV3InterfaceMock tokenUsdFeed = AggregatorV3InterfaceMock(
            _token.clAddr
        );

        uint256 collateralScaled = _tokenValue *
            10 ** getTokenScaleDiff(_token.symbol, _token.addr);

        // Retieves the price of token in USD
        (, int256 tokenUsdPrice, uint256 tokenUpdatedAt, , ) = tokenUsdFeed
            .latestRoundData();

        if (tokenUsdPrice <= 0) revert VaultifyErrors.InvalidPrice();

        if (block.timestamp - tokenUpdatedAt < maxAge) {
            revert VaultifyErrors.PriceStale();
        }

        // Calculates the collateral value in USD
        uint256 collateralUSD = collateralScaled * uint256(tokenUsdPrice);

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
        // Get the price of the TokenToEuro from oracle price Feed;
        AggregatorV3InterfaceMock tokenUsdFeed = AggregatorV3InterfaceMock(
            _token.clAddr
        );

        uint256 collateralScaled = _tokenValue *
            10 ** getTokenScaleDiff(_token.symbol, _token.addr);

        // Retieves the price of token in USD
        (, int256 tokenUsdPrice, uint256 tokenUpdatedAt, , ) = tokenUsdFeed
            .latestRoundData();

        // Calculates the collateral value in USD
        // uint256 collateralUSD = collateralScaled * getPriceAvg(tokenUsdFeed, 4);

        uint256 collateralUSD = collateralScaled * uint256(tokenUsdPrice);

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
        bytes32 _symbol,
        address _tokenAddr
    ) private view returns (uint256 scaleDiff) {
        /// change ERC20 to IERC20 mock
        return _symbol == NATIVE ? 0 : 18 - IERC20Mock(_tokenAddr).decimals();
    }

    function euroToToken(
        VaultifyStructs.Token memory _token,
        uint256 _euroValue
    ) external view returns (uint256) {
        // Get the price of the TokenToEuro from oracle price Fees;
        AggregatorV3InterfaceMock tokenUsdFeed = AggregatorV3InterfaceMock(
            _token.clAddr
        );

        // Retieves the price of token in USD
        (, int256 tokenUsdPrice, uint256 tokenUpdatedAt, , ) = tokenUsdFeed
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
        AggregatorV3InterfaceMock _tokenFeed,
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
