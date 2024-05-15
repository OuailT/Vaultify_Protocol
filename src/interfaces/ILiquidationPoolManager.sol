// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface ILiquidationPoolManager {
    function pool() external view returns (address);
    function distributeFees() external;
    function runLiquidation(uint256 _tokenId) external;
}
