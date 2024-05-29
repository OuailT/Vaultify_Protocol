// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {INFTMetadataGenerator} from "./interfaces/INFTMetadataGenerator.sol";
import {IEUROs} from "./interfaces/IEUROs.sol";
import {ISmartVaultManager} from "./interfaces/ISmartVaultManager.sol";
import {ISmartVault} from "./interfaces/ISmartVault.sol";
import {ISmartVaultDeployer} from "./interfaces/ISmartVaultDeployer.sol";
import {ISmartVaultIndex} from "./interfaces/ISmartVaultIndex.sol";
import {VaultifyErrors} from "./libraries/VaultifyErrors.sol";
import {VaultifyEvents} from "./libraries/VaultifyEvents.sol";
import {VaultifyStructs} from "./libraries/VaultifyStructs.sol";

/// @title SmartVaultManager
/// OUAIL Allows the vault manager to set important  state variables, generate NFT metadata of the vault, deploy a new smart vault.
/// @notice Contract managing vault deployments, controls admin data which dictates behavior of Smart Vaults.
/// @dev Manages fee rates, collateral rates, dependency addresses, managed by The Standard.

contract SmartVaultManager is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 public constant HUNDRED_PRC = 1e5;

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

    modifier onlyLiquidator() {
        require(msg.sender == liquidator, "err-invalid-liquidator");
        _;
    }

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _smartVaultIndex,
        uint256 _mintFeeRate,
        uint256 _burnFeeRate,
        uint256 _swapFeerate,
        address _weth,
        address _swapRouter,
        address _nftMetadataGenerator,
        address _smartVaultDeployer,
        address _protocol,
        address _liquidator
    ) external initializer {
        __Ownable_init(msg.sender);
        setMintFeeRate(_mintFeeRate);
        setBurnFeeRate(_burnFeeRate);
        setSwapFeeRate(_swapFeerate);
        setWethAddress(_weth);
        setSwapRouter2(_swapRouter);
        setNFTMetadataGenerator(_nftMetadataGenerator);
        setSmartVaultDeployer(_smartVaultDeployer);
        setProtocolAddress(_protocol);
        setLiquidatorAddress(_liquidator);
        ISmartVaultIndex smartVaultIndex = ISmartVaultIndex(_smartVaultIndex);
    }

    function createNewVault()
        external
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

    // returns VaultifyStructs.SmartVaultData struct type array
    function getVaults()
        external
        view
        returns (VaultifyStructs.SmartVaultData[] memory)
    {
        // Get vaults who belong to the user by ids from smartcontractIndex;
        uint256[] memory tokenIds = smartVaultIndex.getTokenIds(msg.sender);

        uint256 tokenIdsLengh = tokenIds.length;

        // create fixed sized array to store data of each smart vault based on their IDs
        VaultifyStructs.SmartVaultData[]
            memory vaultData = new VaultifyStructs.SmartVaultData[](
                tokenIdsLengh
            );

        for (uint256 i = 0; i < tokenIdsLengh; i++) {
            uint256 tokenId = tokenIds[i];
            vaultData[i] = VaultifyStructs.SmartVaultData({
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
        VaultifyStructs.Status memory vaultStatus = ISmartVault(
            smartVaultIndex.getVaultAddress(_tokenId)
        ).status();
        return
            // Generate metadata based on the vault status and tokenId
            INFTMetadataGenerator(nftMetadataGenerator).generateNFTMetadata(
                _tokenId,
                vaultStatus
            );
    }

    function liquidateVault(uint256 _tokenId) external onlyLiquidator {
        // Retrieve vault with the tokenId
        ISmartVault vault = ISmartVault(
            smartVaultIndex.getVaultAddress(_tokenId)
        );

        try vault.underCollateralised() returns (bool _undercollateralised) {
            if (!_undercollateralised)
                revert VaultifyErrors.VaultNotUnderCollateralised(
                    address(vault)
                );

            // liquidate vault
            vault.liquidate();

            // REVOKE ROLE
            IEUROs(euros).revokeRole(
                IEUROs(euros).MINTER_ROLE(),
                address(vault)
            );

            IEUROs(euros).revokeRole(
                IEUROs(euros).BURNER_ROLE(),
                address(vault)
            );

            // emit VaultLiquidated()
            emit VaultifyEvents.VaultLiquidated(address(vault));
        } catch {
            revert("other-liquidation-error");
        }
    }

    // Liquidate vault(); todo later;

    // setter functions //
    function totalSupply() external view returns (uint256) {
        return lastTokenId;
    }

    function setMintFeeRate(uint256 _mintFeeRate) public onlyOwner {
        mintFeeRate = _mintFeeRate;
    }

    function setBurnFeeRate(uint256 _burnFeeRate) public onlyOwner {
        burnFeeRate = _burnFeeRate;
    }

    function setSwapFeeRate(uint256 _swapFeerate) public onlyOwner {
        swapFeeRate = _swapFeerate;
    }

    function setWethAddress(address _weth) public onlyOwner {
        weth = _weth;
    }

    function setSwapRouter2(address _swapRouter) public onlyOwner {
        swapRouter2 = _swapRouter;
    }

    function setNFTMetadataGenerator(
        address _nftMetadataGenerator
    ) public onlyOwner {
        nftMetadataGenerator = _nftMetadataGenerator;
    }

    function setSmartVaultDeployer(
        address _smartVaultDeployer
    ) public onlyOwner {
        smartVaultDeployer = _smartVaultDeployer;
    }

    function setProtocolAddress(address _protocol) public onlyOwner {
        protocol = _protocol;
    }

    function setLiquidatorAddress(address _liquidator) public onlyOwner {
        liquidator = _liquidator;
    }

    // // Also Added function to fix bug in LiquidationPool
    // Create a function that get invoked when a burn, mint, transfer of tokens is being made
    function grantPoolBurnApproval(address poolAddr) public onlyOwner {
        // Grant burner role to LiquidityPool for EURO
        IEUROs(euros).grantRole(IEUROs(euros).BURNER_ROLE(), poolAddr);
    }

    function revokePoolBurnApproval(address poolAddr) public onlyOwner {
        // Grant burner role to LiquidityPool for EURO
        IEUROs(euros).revokeRole(IEUROs(euros).BURNER_ROLE(), poolAddr);
    }

    // Triggerd when a NFT is minted or transffered
    function _update(
        address _to,
        uint256 _tokenId,
        address _auth
    ) internal override returns (address) {
        super._update(_to, _tokenId, _auth);
        address _from = _ownerOf(_tokenId);
        smartVaultIndex.transferTokenId(_from, _to, _tokenId);
        if (address(_from) != address(0)) {
            address vaultAddress = smartVaultIndex.getVaultAddress(_tokenId);
            ISmartVault(vaultAddress).setOwner(_to);
        }
        emit VaultifyEvents.VaultTransferred(_tokenId, _from, _to);
    }
}
