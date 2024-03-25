// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEUROs} from "./interfaces/IEUROs.sol";
import {IPriceCalculator} from "./interfaces/IPriceCalculator.sol";
import {ISmartVault} from "./interfaces/ISmartVault.sol";
import {ISmartVaultManager} from "./interfaces/ISmartVaultManager.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {ITokenManager} from "./interfaces/ITokenManager.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {VaultifyErrors} from "./libraries/VaultifyErrors.sol";
import {VaultifyEvents} from "./libraries/VaultifyEvents.sol";

contract SmartVault is ISmartVault {
    using SafeERC20 for IERC20;

    uint8 private constant VERSION = 2;
    bytes32 private constant VAULT_TYPE = bytes32("Euros");

    // Immutable variables
    bytes32 private immutable NATIVE; ///< Symbol of the native asset.
    address public immutable manager; ///< Address of the SmartVaultManager contract.
    IEUROs public immutable EUROs; ///< EUROs token contract interface.
    IPriceCalculator public immutable calculator; ///< Price calculator contract interface.

    // State variables
    address public owner; ///< Owner of the Smart Vault.
    uint256 private mintedEuros; ///< Amount of EUROs minted in this vault.
    bool private liquidated; ///< Flag indicating if the vault has been liquidated.
    ISmartVaultManager private smartVaultManager;

    /// @notice Initializes a new Smart Vault.
    /// @dev Sets initial values for the Smart Vault.
    /// @param _native Symbol of the native asset.
    /// @param _manager Address of the SmartVaultManager contract.
    /// @param _owner Address of the owner of this vault.
    /// @param _euros Address of the EUROs token contract.
    /// @param _priceCalculator Address of the Price Calculator contract.
    constructor(
        bytes32 _native,
        address _manager,
        address _owner,
        address _euros,
        address _priceCalculator
    ) {
        NATIVE = _native;
        owner = _owner;
        manager = _manager;
        EUROs = IEUROs(_euros);
        calculator = IPriceCalculator(_priceCalculator);
        smartVaultManager = ISmartVaultManager(_manager);
    }

    // The vault owner
    /// @notice Modifier to allow only the owner of the vault to call a function.
    modifier onlyVaultOwner() {
        if (owner != msg.sender)
            revert VaultifyErrors.UnauthorizedCalled(msg.sender);
        _;
    }

    modifier onlyVaultManager() {
        if (manager != msg.sender)
            revert VaultifyErrors.UnauthorizedCalled(msg.sender);
        _;
    }

    modifier ifNotLiquidated() {
        if (liquidated) revert VaultifyErrors.LiquidatedVault(address(this));
        _;
    }

    modifier ifEurosMinted(uint256 _amount) {
        if (mintedEuros < _amount)
            revert VaultifyErrors.InsufficientEurosMinted(_amount);
        _;
    }

    receive() external payable {}

    /// @notice Retrieves the Token Manager contract.
    /// @dev Calls the manager contract to get the Token Manager's address.
    /// @return The Token Manager contract.
    function getTokenManager() private view returns (ITokenManager) {
        return ITokenManager(smartVaultManager.tokenManager());
    }

    /// @notice Calculates the total collateral value in EUROs within the vault.
    /// @dev Sums up the EURO value of all accepted tokens in the vault.
    /// @return euros Total collateral value in EUROs.
    function euroCollateral() internal view returns (uint256 euro) {
        // Get accepted tokens by the manager
        ITokenManager.Token[] memory acceptedTokens = getTokenManager()
            .getAcceptedTokens();
        for (uint256 i; i < acceptedTokens.length; i++) {
            ITokenManager.Token memory token = acceptedTokens[i];
            euro += calculator.tokenToEuroAvg(
                token,
                getAssetBalance(token.symbol, token.addr)
            );
        }
    }

    // Mininmum amount out that user can get out of the swap
    function calculateMinimimAmountOut(
        bytes32 _inTokenSymbol,
        bytes32 _outTokenSymbol,
        uint256 _amount
    ) private view returns (uint256) {
        // The percentage of minted token(borrowed token) that must be backed by collateral
        // to keep vault collatalized
        uint256 requiredCollateralValue = (mintedEuros *
            ISmartVaultManager().collateralRate()) /
            ISmartVaultManager().HUNDRED_PRC();

        // The amount of collateral held in the vault in EUROs after the swap
        uint256 collateralValueMinusSwapValue = euroCollateral() -
            calculator.tokenToEur(getToken(_inTokenSymbol), _amount);

        // Before swap make sure that the vault remains collateralized after swap:
        // If collateralValueMinusSwapValue >= requiredCollateralValue = Vault/address(this) remain collateralized after receiving tokenOut.
        // else: The Vault/contract must receive from the swap at least a minimumOut to keep vault collateralized.
        return
            collateralValueMinusSwapValue >= requiredCollateralValue
                ? 0
                : calculator.euroToToken(
                    getToken(_outTokenSymbol),
                    requiredCollateralValue - collateralValueMinusSwapValue
                );
    }

    // Get token address by it token
    function getToken(
        bytes32 _symbol
    ) private view returns (ITokenManager.Token memory _token) {
        ITokenManager.Token[] memory tokens = getTokenManager()
            .getAcceptedTokens();

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].symbol == _symbol) _token = tokens[i];
        }

        if (_token.symbol == bytes32(0))
            revert VaultifyErrors.InvalidTokenSymbol();
    }

    function getAssetBalance(
        bytes32 _sybmol,
        address addr
    ) internal view returns (uint256) {
        _sybmol == NATIVE
            ? address(this).balance
            : IERC20(addr).balanceOf(address(this));
    }

    // Max EUROS token to mint based on the deposited collateral provided In the vault
    function MaxMintableEuros() internal view returns (uint256) {
        return
            (euroCollateral() * smartVaultManager.HUNDRED_PRC()) /
            smartVaultManager.collateralRate();
    }

    // Will return true if the the vault is fully coll
    function fullyCollateralised(uint256 _amount) private view returns (bool) {
        mintedEuros + _amount <= MaxMintableEuros();
    }

    // under collateralised function
    function underCollateralised() public view returns (bool) {
        mintedEuros > MaxMintableEuros();
    }

    function liquidate() external onlyVaultOwner {
        // Check if the vault is collaterlized
        if (!underCollateralised())
            revert VaultifyErrors.VaultNotLiquidatable();

        liquidated = true;
        mintedEuros = 0;
        liquidateNative();
        ITokenManager.Token[] memory tokens = getTokenManager()
            .getAcceptedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            ITokenManager.Token memory token = tokens[i];
            if (token.symbol != NATIVE) {
                liquidateERC20(IERC20(token.addr));
            }
        }
    }

    function liquidateNative() private {
        uint EthBal = address(this).balance;
        // Check if the vault has enough ETH balance
        if (EthBal != 0) {
            (bool succ, ) = payable(smartVaultManager.liquidator()).call{
                value: EthBal
            }("");
            if (!succ) revert VaultifyErrors.NativeTxFailed();
        }
    }

    function liquidateERC20(IERC20 _token) private {
        uint256 Erc20Bal = _token.balanceOf(address(this));
        // Check if the contract has enough balance for the specific token
        if (_token.balanceOf(address(this)) != 0) {
            _token.safeTransfer(smartVaultManager.liquidator(), Erc20Bal);
        }
    }

    function borrowMint(
        uint256 _amount,
        address _to
    ) external ifNotLiquidated onlyVaultOwner {
        // Get the borrow/mint Euro Fee
        uint256 fee = (_amount * smartVaultManager.mintFeeRate()) /
            smartVaultManager.HUNDRED_PRC();
        if (!fullyCollateralised(_amount)) {
            revert VaultifyErrors.UnderCollateralisedVault(address(this));
        }

        mintedEuros += _amount;
        EUROs.mint(_to, _amount - fee);
        // Fees goes to the vault liquidator
        EUROs.mint(smartVaultManager.liquidator(), fee);
        emit VaultifyEvents.EUROsMinted(_to, _amount - fee, fee);
    }

    function burnEuros(uint256 _amount) external ifEurosMinted(_amount) {
        // Check if this contract has enough allowance of euro tokens to burn;
        bool euroApproved = IERC20(EUROs).allowance(
            msg.sender,
            address(this)
        ) >= _amount;

        if (!euroApproved) revert VaultifyErrors.NotEnoughAllowance(_amount);

        uint256 fee = (_amount * smartVaultManager.burnFeeRate()) /
            smartVaultManager.HUNDRED_PRC();

        mintedEuros -= _amount;
        EUROs.burn(msg.sender, _amount - fee);

        // Execute approve function in the context of the caller msg.sender to approve this contract
        // to spend/transfer the fees to the liquidator
        (bool succ, ) = address(EUROs).delegatecall(
            abi.encodeWithSignature(
                "approve(address,uint256)",
                address(this),
                fee
            )
        );

        if (!succ) revert VaultifyErrors.DelegateCallFailed();

        IERC20(address(EUROs)).safeTransferFrom(
            msg.sender,
            smartVaultManager.liquidator(),
            fee
        );

        emit VaultifyEvents.EUROsBurned(_amount, fee);
    }

    function getSwapAddressFor(bytes32 _symbol) private view returns (address) {
        ITokenManager.Token memory _token = getToken(_symbol);
        return
            _token.addr == address(0) ? smartVaultManager.weth() : _token.addr;
    }

    function canRemoveCollateral(
        ITokenManager.Token memory _token,
        uint256 _amount
    ) private view returns (bool) {
        if (mintedEuros == 0) return true;

        // The Maximum amount of EUROS to mint based on the collateral held in the vault.
        uint256 currentMintable = MaxMintableEuros();

        // The avg in EUROS of the amount of token to remove from the vault
        uint256 euroValueToRemove = calculator.tokenToEuroAvg(_token, _amount);

        // Ensures that the minted amount of minted EURO in the vault still backed by collateral after removing some collateral.
        return
            currentMintable >= euroValueToRemove &&
            mintedEuros <= currentMintable - euroValueToRemove;
    }

    function removeNativeCollateral(
        uint256 _amount,
        address payable _to
    ) external onlyVaultOwner {
        bool canRemoveNative = canRemoveCollateral(getToken(NATIVE), _amount);

        if (!canRemoveNative) revert VaultifyErrors.NativeRemove_Err();
        if (_amount < 0) revert VaultifyErrors.ZeroValue();
        if (_to == address(0)) revert VaultifyErrors.ZeroAddress();

        (bool succ, ) = _to.call{value: _amount}("");
        if (!succ) revert VaultifyErrors.NativeTxFailed();

        emit VaultifyEvents.NativeCollateralRemoved(NATIVE, _amount, _to);
    }

    function removeERC20Collateral(
        bytes32 _symbol,
        uint256 _amount,
        address _to
    ) external onlyVaultOwner {
        ITokenManager.Token memory _token = getToken(_symbol);

        bool canRemoveERC20 = canRemoveCollateral(_token, _amount);

        if (!canRemoveERC20) revert VaultifyErrors.TokenRemove_Err();
        if (_amount < 0) revert VaultifyErrors.ZeroValue();
        if (_to == address(0)) revert VaultifyErrors.ZeroAddress();

        IERC20(_token.addr).safeTransfer(_to, _amount);

        emit VaultifyEvents.ERC20CollateralRemoved(_symbol, _amount, _to);
    }

    function executeNativeSwapAndFee(
        ISwapRouter.ExactInputSingleParams memory _params,
        uint256 _swapFee
    ) private returns (uint256 amountOut) {
        // Send fees to liquidator
        (bool succ, ) = payable(smartVaultManager.liquidator()).call{
            value: _swapFee
        }("");

        if (!succ) revert VaultifyErrors.SwapFeeNativeFailed();

        // Execute The swap
        ISwapRouter(smartVaultManager.swapRouter2()).exactInputSingle{
            value: _params.amountIn
        }(_params);

        emit VaultifyEvents.NativeSwapExecuted(
            _params.amountIn,
            _swapFee,
            amountOut
        );
    }

    function executeERC20SwapAndFee(
        ISwapRouter.ExactInputSingleParams memory _params,
        uint256 _swapFee
    ) private returns (uint256 amountOut) {
        // Send fees to liquidator
        IERC20(_params.tokenIn).safeTransfer(
            smartVaultManager.liquidator(),
            _swapFee
        );

        // approve the router to spend amountin on the vault behalf to conduct the swap
        IERC20(_params.tokenIn).safeApprove(
            smartVaultManager.swapRouter2(),
            _params.amountIn
        );

        // Execute the Swap
        amountOut = ISwapRouter(smartVaultManager.swapRouter2())
            .exactInputSingle(_params);

        // If user Swap AToken/WETH then we convert WETH to ETH
        IWETH weth = IWETH(smartVaultManager.weth());

        // Convert potentially received weth to ETH
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) weth.withdraw(wethBalance);

        emit VaultifyEvents.ERC20SwapExecuted(
            _params.amountIn,
            _swapFee,
            amountOut
        );
    }

    function swap(
        bytes32 _inTokenSybmol,
        bytes32 _outTokenSymbol,
        uint256 _amount
    ) external onlyVaultOwner {
        // Calculate the fee swap
        uint256 swapFee = (_amount * smartVaultManager.swapFee()) /
            smartVaultManager.HUNDRED_PRC();

        address inToken = getSwapAddressFor(_inTokenSybmol);

        uint256 minimumAmountOut = calculateMinimimAmountOut(
            _inTokenSybmol,
            _outTokenSymbol,
            _amount
        );

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: inToken,
                tokenOut: getSwapAddressFor(_outTokenSymbol),
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amount - swapFee,
                amountOutMinimum: minimumAmountOut,
                sqrtPriceLimitX96: 0
            });

        inToken == smartVaultManager.weth()
            ? executeNativeSwapAndFee(params, swapFee)
            : executeERC20SwapAndFee(params, swapFee);
    }

    function setOwner(address _newOwner) external onlyVaultManager {
        owner = _newOwner;
    }
}
