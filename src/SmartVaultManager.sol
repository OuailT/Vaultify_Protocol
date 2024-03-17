// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {INFTMetadataGenerator} from "./interfaces/INFTMetadataGenerator.sol";
import {IEUROs} from "./interfaces/IEUROs.sol";
import {ISmartVaultManager} from "./interfaces/ISmartVaultManager.sol";
import {ISmartVaultManagerV2} from "./interfaces/ISmartVaultManagerV2.sol";
import {ISmartVault} from "./interfaces/ISmartVault.sol";
import {ISmartVaultDeployer} from "./interfaces/ISmartVaultDeployer.sol";
import {ISmartVaultIndex} from "./interfaces/ISmartVaultIndex.sol";
import {VaultifyErrors} from "./libraries/VaultifyErrors.sol";
import {VaultifyEvents} from "./libraries/VaultifyEvents.sol";

/// @title SmartVaultManagerV5
/// OUAIL Allows the vault manager to set important  state variables, generate NFT metadata of the vault, deploy a new smart vault.
/// @notice Contract managing vault deployments, controls admin data which dictates behavior of Smart Vaults.
/// @dev Manages fee rates, collateral rates, dependency addresses, managed by The Standard.

contract SmartVaultManagerV5 is
    ISmartVaultManager,
    ISmartVaultManagerV2,
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    address public protocol;
    address public liquidator;
    address public euros;
    uint256 public collateralRate;
    address public tokenManager;
    address public smartVaultDeployer;
    ISmartVaultIndex private smartVaultIndex;
    uint256 private lastTokenId;
    address public nftMetadataGenerator;
    uint256 public mintFeeRate;
    uint256 public burnFeeRate;
    uint256 public swapFeeRate;
    address public weth;
    address public swapRouter;
    address public swapRouter2;

    // create a struct to store the vault data
    struct SmartVaultData {
        uint256 tokenId;
        uint256 collateralRate;
        uint256 mintFeeRate;
        uint256 burnFeeRate;
        ISmartVault.Status status;
    }

    function initialize() public initializer {}

    // Exercice: Create a function that allow user to mint smart vault
    // params: none;
    // returns the address of the smart vault;
    function createNewVault()
        public
        view
        returns (uint256 tokenId, address vault)
    {
        // increment tokenId by 1
        tokenId = lastTokenId + 1;

        // Mint the smart vault to the caller
        _safeMint(msg.sender, tokenId);

        // set the tokenId to the last token Id
        lastTokenId = tokenId;

        // Deploy the smart vault
        vault = ISmartVaultDeployer(smartVaultDeployer).deploy(
            address(this),
            msg.sender,
            euros
        );

        // Add the vault to the smart vault index
        smartVaultIndex.addVaultAddress(lastTokenId, payable(vault));

        // Grante the vault Burn and MINT role
        IEUROs(euros).grantRole(IEUROs(euros).MINTER_ROLE(), vault);
        IEUROs(euros).grantRole(IEUROs(euros).BURNER_ROLE(), vault);

        emit VaultifyEvents.VaultDeployed(vault, msg.sender, euros, tokenId);
    }

    // returns SmartVaultData struct type array
    function getVaults() external view returns (SmartVaultData[] memory) {
        // Get vaults who belong to the user by ids from smartcontractIndex;
        uint256[] memory tokenIds = smartVaultIndex.getTokenIds(msg.sender);

        uint256 tokenIdsLengh = tokenIds.length;

        // create fixed sized array to store data of each smart vault based on their IDs
        SmartVaultData[] memory vaultData = new SmartVaultData[](tokenIdsLengh);

        for (uint256 i = 0; i < tokenIdsLengh; i++) {
            uint256 tokenId = tokenIds[i];
            vaultData[i] = SmartVaultData({
                tokenId: tokenId,
                collateralRate: collateralRate,
                mintFeeRate: mintFeeRate,
                burnFeeRate: burnFeeRate,
                status: ISmartVault(smartVaultIndex.getVaultAddress(tokenId))
                    .status()
            });
        }

        return vaultData;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view virtual override returns (string memory) {
        ISmartVault.Status memory vaultStatus = ISmartVault(
            smartVaultIndex.getVaultAddress(_tokenId)
        ).status();
        return
            // Generate metadata based on the vault status and tokenId
            INFTMetadataGenerator(nftMetadataGenerator).generateNFTMetadata(
                _tokenId,
                vaultStatus
            );
    }

    // setter functions //
    function totalSupply() external view returns (uint256) {
        return lastTokenId;
    }

    function setMintFeeRate(uint256 _rate) external onlyOwner {
        mintFeeRate = _rate;
    }

    function setBurnFeeRate(uint256 _rate) external onlyOwner {
        burnFeeRate = _rate;
    }

    function setSwapFeeRate(uint256 _rate) external onlyOwner {
        swapFeeRate = _rate;
    }

    function setWethAddress(address _weth) external onlyOwner {
        weth = _weth;
    }

    function setSwapRouter2(address _swapRouter) external onlyOwner {
        swapRouter2 = _swapRouter;
    }

    function setNFTMetadataGenerator(
        address _nftMetadataGenerator
    ) external onlyOwner {
        nftMetadataGenerator = _nftMetadataGenerator;
    }

    function setSmartVaultDeployer(
        address _smartVaultDeployer
    ) external onlyOwner {
        smartVaultDeployer = _smartVaultDeployer;
    }

    function setProtocolAddress(address _protocol) external onlyOwner {
        protocol = _protocol;
    }

    function setLiquidatorAddress(address _liquidator) external onlyOwner {
        liquidator = _liquidator;
    }

    // Create a function that get invoked when a burn, mint, transfer of tokens is being made
    // NOTE: Todo later.
}
