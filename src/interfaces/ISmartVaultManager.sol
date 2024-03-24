// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface ISmartVaultManager {
    function HUNDRED_PRC() external view returns (uint256);
    function tokenManager() external view returns (address);
    function liquidator() external view returns (address);
    function protocol() external view returns (address);
    function burnFeeRate() external view returns (uint256);
    function mintFeeRate() external view returns (uint256);
    function collateralRate() external view returns (uint256);
    function liquidateVault(uint256 _tokenId) external;
    function totalSupply() external view returns (uint256);
    function swapRouter2() external view returns (address);
    function weth() external view returns (address);
    function swapRouter() external view returns (address);
    function swapFeeRate() external view returns (uint256);
}
