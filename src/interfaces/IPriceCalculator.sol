// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./ITokenManager.sol";

interface IPriceCalculator {
    function tokenToEuroAvg(
        ITokenManager.Token memory _token,
        uint256 _amount
    ) external view returns (uint256);

    function tokenToEur(
        ITokenManager.Token memory _token,
        uint256 _amount
    ) external view returns (uint256);

    function euroToToken(
        ITokenManager.Token memory _token,
        uint256 _amount
    ) external view returns (uint256);
}
