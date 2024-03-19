// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.17;

// import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol" as Chainlink;
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "contracts/interfaces/IPriceCalculator.sol";

// contract PriceCalculator is IPriceCalculator {
//     bytes32 private immutable NATIVE;

//     Chainlink.AggregatorV3Interface public immutable clEurUsd;

//     constructor(bytes32 _native, address _clEurUsd) {
//         NATIVE = _native;
//         clEurUsd = Chainlink.AggregatorV3Interface(_clEurUsd);
//     }


//     function avgPrice(
//         uint8 _hours,
//         Chainlink.AggregatorV3Interface _priceFeed
//     ) private view returns (uint256) {
        
//         // the get the startPeriod from were we want to calculate the average price(last 5,4 hours);
//         uint256 startPeriod = block.timestamp - _hours * 1 hours;

//         // It retrieves the latest round data from the Chainlink price feed.
//         uint256 roundTS; // updatedAT
//         uint80 roundId;
//         int256 answer; 
//         (roundId, answer, , roundTS, ) = _priceFeed.latestRoundData();

//         // accumulate the sum of prices
//         uint256 accummulatedRoundPrices = uint256(answer);

//         // count the number of rounds to use for averaging
//         uint256 roundCount = 1;

//         // While roundTS > startPeriod means that this loops will go thought until
//         // lasttimethe price updated is less that the start period.

//         // Case 1: RoundId = 10 
//         while (roundTS > startPeriod && roundId > 1) {
//             // 1- initial roundId = 1O
//             roundId--; // 4- increment to 9
//             try _priceFeed.getRoundData(roundId) {
//                 // 2- fetch data for roundId 10
//                 // 5- fetch data for round 9
//                 (, answer, , roundTS, ) = _priceFeed.getRoundData(roundId);
//                 // 3- update both values
//                 accummulatedRoundPrices += uint256(answer);
//                 roundCount++;
//             } catch {
//                 continue;
//             }
//         }
//         return accummulatedRoundPrices / roundCount;
//     }
    

//     // Melo Metho
//     function tokenToEur(
//         ITokenManager.Token memory _token, // WBTC
//         uint256 _tokenValue // 100 WBTC
//     ) external view returns (uint256) {
//         // Retrieves the Chainlink price feed interface for the token's(ETH) USD price
//         Chainlink.AggregatorV3Interface tokenUsdClFeed = Chainlink
//             .AggregatorV3Interface(_token.clAddr);

//         // Scales the token value based on its symbol and address
//         uint256 scaledCollateral = _tokenValue *
//             10 ** getTokenScaleDiff(_token.symbol, _token.addr);

//         // scaledCollateral = _tokenValue * 10 ** 0 : anything number power 0 = 1 therefore = _tokenValue * 1 = _tokenValue.
//         // this means the _tokenValue is already 18 scaled.

//         // In case decimals = 18 - 8 = 10; _tokenValue * 10 ** 10 =

//         // Retrieves the latest round data for the token's(WBTC) USD price
//         (, int256 _tokenUsdPrice, , , ) = tokenUsdClFeed.latestRoundData();

//         // Calculates the collateral value in USD
//         uint256 collateralUsd = scaledCollateral * uint256(_tokenUsdPrice);

//         // Retrieves the latest round data for the EUR/USD price feed
//         (, int256 eurUsdPrice, , , ) = clEurUsd.latestRoundData();

//         // Converts the collateral value from USD to EUR
//         // Division of collateralUSD by the price of EURO in USD =  whoch give us the equivalent in EURO
//         // 120 / 1.2(EUROUSD) = 100 EUROs
//         return collateralUsd / uint256(eurUsdPrice);
//     }

//     // To understand more later...
//     function getTokenScaleDiff(
//         bytes32 _symbol,
//         address _tokenAddress
//     ) private view returns (uint256 scaleDiff) {
//         return _symbol == NATIVE ? 0 : 18 - ERC20(_tokenAddress).decimals(); //
//     }

//     function eurToToken(
//         ITokenManager.Token memory _token,
//         uint256 _eurValue
//     ) external view returns (uint256) {
        
//         // Retrieves the Chainlink price feed interface for the token's USD price
//         Chainlink.AggregatorV3Interface tokenUsdClFeed = Chainlink
//             .AggregatorV3Interface(_token.clAddr);

//         // Retrieves the latest round data for the token's USD price
//         (, int256 tokenUsdPrice, , , ) = tokenUsdClFeed.latestRoundData();
        
//         // Retrieves the latest round data for the EUR/USD price feed
//         (, int256 eurUsdPrice, , , ) = clEurUsd.latestRoundData();

//         return
//             // Calculates the token value in EUR
//             (_eurValue * uint256(eurUsdPrice)) // EURO * EURO/USD get the equivalent value in USD / 
//             uint256(tokenUsdPrice) / // USD / token/USD price = value in token 
//             10 ** getTokenScaleDiff(_token.symbol, _token.addr);
//     }
// }
