// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

library VaultifyEvents {
    // Smart vault Manager Event //
    event VaultDeployed(
        address indexed vaultAddress,
        address indexed owner,
        address vaultTokenType,
        uint256 tokenId
    );
    event VaultLiquidated(address indexed vaultAddress);
    event VaultTransferred(uint256 indexed tokenId, address from, address to);
}
