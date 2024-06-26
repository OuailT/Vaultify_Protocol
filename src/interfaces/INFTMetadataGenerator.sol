// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";

interface INFTMetadataGenerator {
    function generateNFTMetadata(
        uint256 _tokenId,
        VaultifyStructs.VaultStatus memory _vaultStatus
    ) external view returns (string memory);
}
