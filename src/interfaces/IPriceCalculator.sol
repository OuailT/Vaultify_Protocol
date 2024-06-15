// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";

interface IPriceCalculator {
    function tokenToEuro(
        VaultifyStructs.Token memory _token,
        uint256 _tokenValue
    ) external view returns (uint256);
    function tokenToEuroAvg(
        VaultifyStructs.Token memory _token,
        uint256 _tokenValue
    ) external view returns (uint256);
    function euroToToken(
        VaultifyStructs.Token memory _token,
        uint256 _euroValue
    ) external view returns (uint256);
}
