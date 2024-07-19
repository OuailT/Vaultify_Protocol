// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface ILiquidationPoolManager {
    function pool() external view returns (address);
    function executeLiquidation(uint256 _tokenId) external;
    function createLiquidityPool() external returns (address);
    function allocateFeesAndAssetsToPool() external;
    function distributeEurosFees() external;
}
