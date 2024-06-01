// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";

interface ISmartVaultManagerMock {
    function HUNDRED_PRC() external view returns (uint256);
    function tokenManager() external view returns (address);
    function liquidator() external view returns (address);
    function protocol() external view returns (address);
    function burnFeeRate() external view returns (uint256);
    function mintFeeRate() external view returns (uint256);
    function collateralRate() external view returns (uint256);
    function liquidateVault(uint256 _tokenId) external;
    function swapRouter2() external view returns (address);
    function weth() external view returns (address);
    function swapRouter() external view returns (address);
    function swapFeeRate() external view returns (uint256);
    function setLiquidator(address _liquidator) external;
    function initialize(
        address,
        uint256,
        uint256,
        uint256,
        address,
        address,
        address,
        address,
        address,
        address,
        address
    ) external;
    function setMintFeeRate(uint256 _mintFeeRate) external;
    function setBurnFeeRate(uint256 _burnFeeRate) external;
    function setSwapFeeRate(uint256 _swapFeerate) external;
    function setWethAddress(address _weth) external;
    function setSwapRouter2(address _swapRouter) external;
    function setNFTMetadataGenerator(address _nftMetadataGenerator) external;
    function setSmartVaultDeployer(address _smartVaultDeployer) external;
    function setProtocolAddress(address _protocol) external;
    function setLiquidatorAddress(address _liquidator) external;
    function grantPoolBurnApproval(address poolAddr) external;
    function revokePoolBurnApproval(address poolAddr) external;
    function createNewVault() external returns (uint256 tokenId, address vault);
    function getVaults()
        external
        view
        returns (VaultifyStructs.SmartVaultData[] memory);
    function tokenURI(uint256 _tokenId) external view returns (string memory);
}
