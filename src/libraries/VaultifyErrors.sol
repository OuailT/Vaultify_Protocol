// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

library VaultifyErrors {
    //*** Price Calculator.sol Errors***//
    error PriceStale();
    error InvalidPrice();

    //*** SmartVault.sol Erros  ***//
    error UnauthorizedCalled(address caller);
    error VaultUnderColl();
}
