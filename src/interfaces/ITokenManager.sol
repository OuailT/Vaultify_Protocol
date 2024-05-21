// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";
interface ITokenManager {
    function getAcceptedTokens()
        external
        view
        returns (VaultifyStructs.Token[] memory);

    function getToken(
        bytes32
    ) external view returns (VaultifyStructs.Token memory);

    function getTokenIfExists(
        address
    ) external view returns (VaultifyStructs.Token memory);

    function addAcceptedToken(address, address) external;
}
