// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

library VaultifyStructs {
    // Tokens
    struct Token {
        bytes32 symbol;
        address addr;
        uint8 dec;
        address clAddr;
        uint8 clDec;
    }

    struct Asset {
        Token token;
        uint256 amount;
    }

    struct SmartVaultAssets {
        VaultifyStructs.Token token;
        uint256 amount;
        uint256 collateralValue;
    }

    struct Status {
        address vaultAddress;
        uint256 minted;
        uint256 maxMintable;
        uint256 totalCollateralValue;
        SmartVaultAssets[] collateral;
        bool liquidated;
        uint8 version;
        bytes32 vaultType;
    }

    // create a struct to store the vault data
    struct SmartVaultData {
        uint256 tokenId;
        uint256 collateralRate;
        uint256 mintFeeRate;
        uint256 burnFeeRate;
        Status status;
    }
}
