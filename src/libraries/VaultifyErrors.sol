// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

library VaultifyErrors {
    //*** Price Calculator.sol Errors***//
    error PriceStale();
    error InvalidPrice();

    //*** SmartVault.sol Erros  ***//
    error InsufficientBalance(address caller, uint256 balance, uint256 amount);
    error NotEnoughEthBalance();
    error EmergencyStateNotActive();
    error NothingToRepay();
    error ZeroAmountNotAllowed();
    error NotEnoughTokenBalance();
    error UnauthorizedCaller(address caller);
    error VaultUnderColl();
    error LiquidatedVault(address vault);
    error UnderCollateralizedVault(address vault);
    error InsufficientEurosMinted(uint256 _value);
    error NotEnoughAllowance(uint256 _value);
    error DelegateCallFailed();
    error InvalidTokenSymbol();
    error SwapFeeNativeFailed();
    error VaultNotLiquidatable();
    error NativeTxFailed();
    error ZeroValue();
    error ZeroAddress();
    error NativeRemovalNotAllowed();
    error TokenRemovalNotAllowed();
    error VaultNotUnderCollateralized(address vault);
    error NotEnoughEurosAllowance();
    error NotEnoughTstAllowance();
    error InvalidDecrementAmount();
    error Incorrect_MinAmountOut(string message);
    error ExcessiveRepayAmount(uint256 borrowed, uint256 amount);
}
