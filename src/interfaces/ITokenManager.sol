// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";
interface ITokenManager {
    function getAcceptedTokens()
        external
        view
        returns (VaultifyStructs.Token[] memory);

    function getToken(
        bytes32 _symbol
    ) external view returns (VaultifyStructs.Token memory token);

    function getTokenIfExists(
        address _tokenAddr
    ) external view returns (VaultifyStructs.Token memory token);

    function addAcceptedToken(address _token, address _chainlinkFeed) external;

    function removeAcceptedToken(bytes32 _symbol) external;
}
