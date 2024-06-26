// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

library VaultifyStructs {
    // Tokens
    struct Token {
        bytes32 symbol;
        address addr;
        uint8 dec;
        address clAddr; // oracle address
        uint8 clDec;
    }

    // Liquidated assets held by the liquation Pool Manager when run liquidation.
    struct Asset {
        Token token;
        uint256 amount;
    }

    // Assets held as collateral in the smart vault
    struct SmartVaultAssets {
        VaultifyStructs.Token token;
        uint256 amount;
        uint256 collateralValue;
    }

    // The Status of the smart vault
    struct VaultStatus {
        address vaultAddress;
        uint256 borrowedAmount;
        uint256 maxBorrowableEuros;
        uint256 totalCollateralValue;
        SmartVaultAssets[] collateralAssets;
        bool isLiquidated;
        uint8 version;
        bytes32 vaultType;
    }

    // to store the vault data
    struct SmartVaultData {
        uint256 tokenId;
        uint256 collateralRate;
        uint256 mintFeeRate;
        uint256 burnFeeRate;
        VaultStatus status;
    }
}
