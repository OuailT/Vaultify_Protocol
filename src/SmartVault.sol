// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEUROs} from "src/interfaces/IEUROs.sol";
import {IPriceCalculator} from "src/interfaces/IPriceCalculator.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {ISmartVaultManager} from "src/interfaces/ISmartVaultManager.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import {ITokenManager} from "src/interfaces/ITokenManager.sol";
import {VaultifyErrors} from "src/libraries/VaultifyErrors.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";

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
    uint256 private borrowedEuros; ///< Amount of EUROs minted in this vault.
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
        if (owner != msg.sender) revert VaultifyErrors.UnauthorizedCaller();
        _;
    }

    modifier onlyVaultManager() {
        if (manager != msg.sender) revert VaultifyErrors.UnauthorizedCaller();
        _;
    }

    modifier ifNotLiquidated() {
        if (liquidated) revert VaultifyErrors.LiquidatedVault(address(this));
        _;
    }

    modifier requireNonZeroAmount(uint256 _amount) {
        if (_amount == 0) {
            revert VaultifyErrors.ZeroAmountNotAllowed();
        }
        _;
    }

    modifier ensureValidRepayAmount(uint256 _amount) {
        if (_amount > borrowedEuros)
            revert VaultifyErrors.ExcessiveRepayAmount(borrowedEuros, _amount);
        _;
    }

    receive() external payable {}

    /// @notice Retrieves the Token Manager contract.
    /// @dev Calls the manager contract to get the Token Manager's address.
    /// @return The Token Manager contract.
    function getTokenManager() public view returns (ITokenManager) {
        return ITokenManager(smartVaultManager.tokenManager());
    }

    /// @notice Calculates the total collateral value in EUROs within the vault.
    /// @dev Sums up the EURO value of all accepted tokens in the vault.
    function totalCollateralInEuros() internal view returns (uint256 euro) {
        // Get accepted tokens by the manager
        VaultifyStructs.Token[] memory acceptedTokens = getTokenManager()
            .getAcceptedTokens();
        for (uint256 i; i < acceptedTokens.length; i++) {
            VaultifyStructs.Token memory token = acceptedTokens[i];
            euro += calculator.tokenToEuroAvg(
                token,
                getAssetBalance(token.symbol, token.addr)
            );
        }
    }

    /**
     * @notice Calculates the minimum amount out required to keep the vault collateralized after a swap.
     * @param _inTokenSymbol The symbol of the input token.
     * @param _outTokenSymbol The symbol of the output token.
     * @param _amount The amount of the input token.
     * @param _minAmountOut The minimum amount of the output token expected by the user.
     * @return The minimum amount of the output token required.
     */
    function calculateMinimimAmountOut(
        bytes32 _inTokenSymbol,
        bytes32 _outTokenSymbol,
        uint256 _amount,
        uint256 _minAmountOut
    ) private view returns (uint256) {
        // The percentage of minted token(borrowed token) that must be backed by collateral
        // to keep vault collatalized
        uint256 requiredCollateralValue = (borrowedEuros *
            smartVaultManager.collateralRate()) /
            smartVaultManager.HUNDRED_PRC();

        // The amount of collateral held in the vault in EUROs after the swap
        uint256 collateralValueMinusSwapValue = totalCollateralInEuros() -
            calculator.tokenToEuroAvg(getToken(_inTokenSymbol), _amount);

        // 10 PAXG =>
        // Before swap make sure that the vault remains collateralized after swap:
        // If collateralValueMinusSwapValue >= requiredCollateralValue = Vault/address(this) remain collateralized after receiving tokenOut.
        // else: The Vault/contract must receive from the swap at least a minimumOut to keep vault collateralized.
        return
            collateralValueMinusSwapValue >= requiredCollateralValue
                ? _minAmountOut
                : calculator.euroToToken(
                    getToken(_outTokenSymbol),
                    requiredCollateralValue - collateralValueMinusSwapValue
                );
    }

    /**
     * @notice Retrieves the token address by its symbol.
     * @param _symbol The symbol of the token.
     * @return _token The token details.
     */
    function getToken(
        bytes32 _symbol
    ) private view returns (VaultifyStructs.Token memory _token) {
        VaultifyStructs.Token[] memory tokens = getTokenManager()
            .getAcceptedTokens();

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].symbol == _symbol) _token = tokens[i];
        }

        if (_token.symbol == bytes32(0))
            revert VaultifyErrors.InvalidTokenSymbol();
    }

    /**
     * @notice Provides the current status of the vault.
     * @return The status details of the vault.
     */
    function vaultStatus()
        external
        view
        returns (VaultifyStructs.VaultStatus memory)
    {
        return
            VaultifyStructs.VaultStatus({
                vaultAddress: address(this),
                borrowedAmount: borrowedEuros,
                maxBorrowableEuros: calculateMaxBorrowableEuros(),
                totalCollateralValue: totalCollateralInEuros(),
                collateralAssets: getAssets(),
                isLiquidated: liquidated,
                version: VERSION,
                vaultType: VAULT_TYPE
            });
    }

    /**
     * @notice Retrieves the assets held in the vault.
     * @return An array of the assets in the vault.
     */
    function getAssets()
        private
        view
        returns (VaultifyStructs.SmartVaultAssets[] memory)
    {
        VaultifyStructs.Token[] memory acceptedTokens = getTokenManager()
            .getAcceptedTokens();

        // Create Fixed sized Array based on the length of the acceptedTokens.add.
        VaultifyStructs.SmartVaultAssets[]
            memory assets = new VaultifyStructs.SmartVaultAssets[](
                acceptedTokens.length
            );
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            VaultifyStructs.Token memory token = acceptedTokens[i];
            uint256 assetBalance = getAssetBalance(token.symbol, token.addr);
            assets[i] = VaultifyStructs.SmartVaultAssets(
                token,
                assetBalance,
                calculator.tokenToEuroAvg(token, assetBalance)
            );
        }
        return assets;
    }

    /**
     * @notice Gets the balance of a specific asset in the vault.
     * @param _symbol The symbol of the asset.
     * @param addr The address of the asset.
     * @return The balance of the asset.
     */
    // Change this to IERC20Mock
    function getAssetBalance(
        bytes32 _symbol,
        address addr
    ) public view returns (uint256) {
        return
            _symbol == NATIVE
                ? address(this).balance
                : IERC20(addr).balanceOf(address(this)); // change it to IERC20 mocks
    }

    /**
     * @notice Calculates the maximum amount of EUROs that can be borrowed based on the current collateral.
     * @return The maximum borrowable EUROs.
     */
    function calculateMaxBorrowableEuros() internal view returns (uint256) {
        return
            (totalCollateralInEuros() * smartVaultManager.HUNDRED_PRC()) /
            smartVaultManager.collateralRate();
    }

    /**
     * @notice Checks if the vault will remain fully collateralized after minting a certain amount.
     * @param _amount The amount to mint.
     * @return True if the vault remains fully collateralized, otherwise false.
     */
    function fullyCollateralized(uint256 _amount) private view returns (bool) {
        return borrowedEuros + _amount <= calculateMaxBorrowableEuros();
    }

    /**
     * @notice Checks if the vault is under-collateralized.
     * @return True if the vault is under-collateralized, otherwise false.
     */
    function underCollateralized() public view returns (bool) {
        return borrowedEuros > calculateMaxBorrowableEuros();
    }

    /**
     * @notice Liquidates the vault if it is under-collateralized.
     */
    function liquidate() external onlyVaultManager {
        // Check if the vault is collaterlized
        if (!underCollateralized())
            revert VaultifyErrors.VaultNotLiquidatable();

        liquidated = true;
        borrowedEuros = 0;
        liquidateNative();
        VaultifyStructs.Token[] memory tokens = getTokenManager()
            .getAcceptedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            VaultifyStructs.Token memory token = tokens[i];
            if (token.symbol != NATIVE) {
                liquidateERC20(IERC20(token.addr));
            }
        }
    }

    /**
     * @notice Liquidates the native currency held in the vault.
     */
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

    /**
     * @notice Liquidates the ERC20 tokens held in the vault.
     * @param _token The ERC20 token to liquidate.
     */
    function liquidateERC20(IERC20 _token) private {
        uint256 Erc20Bal = _token.balanceOf(address(this));
        // Check if the contract has enough balance for the specific token
        if (_token.balanceOf(address(this)) != 0) {
            _token.safeTransfer(smartVaultManager.liquidator(), Erc20Bal);
        }
    }

    /**
     * @notice Borrows EURO tokens and transfers them to a specified address.
     * @param _to The address to receive the borrowed EUROs.
     * @param _amount The amount of EUROs to borrow.
     */
    function borrow(
        address _to,
        uint256 _amount
    ) external ifNotLiquidated onlyVaultOwner requireNonZeroAmount(_amount) {
        // Get the borrow/mint Euro Fee
        uint256 fee = (_amount * smartVaultManager.mintFeeRate()) /
            smartVaultManager.HUNDRED_PRC();

        if (!fullyCollateralized(_amount)) {
            revert VaultifyErrors.UnderCollateralizedVault(address(this));
        }

        borrowedEuros += _amount;

        EUROs.mint(_to, _amount - fee);

        // Fees goes to the vault liquidator
        EUROs.mint(smartVaultManager.liquidator(), fee);

        emit VaultifyEvents.EUROsMinted(_to, _amount - fee, fee);
    }

    // TODO Add RepayFull function

    /**
     * @notice Repays borrowed EURO tokens from the caller's account.
     * @param _amount The amount of EURO tokens to repay.
     */
    function repay(
        uint256 _amount
    )
        external
        ensureValidRepayAmount(_amount)
        onlyVaultOwner
        requireNonZeroAmount(_amount)
    {
        // Check if this contract has enough allowance of euro tokens to burn;
        bool euroApproved = IERC20(EUROs).allowance(
            msg.sender,
            address(this)
        ) >= _amount;

        // we already give the the contract the allowance amount which deduct the fee from?
        // Why do we give the contract an approval again throught delegate call to spend the fee as the fee is already part of the amount

        if (!euroApproved) revert VaultifyErrors.NotEnoughAllowance(_amount);

        uint256 fee = (_amount * smartVaultManager.burnFeeRate()) /
            smartVaultManager.HUNDRED_PRC();
        // 50_000 EUROS - Fee = Amount to brun therefore, burn can only
        // with the amount that alice has of euros.

        borrowedEuros -= _amount;

        EUROs.burn(msg.sender, _amount - fee);

        IERC20(address(EUROs)).safeTransferFrom(
            msg.sender,
            smartVaultManager.liquidator(),
            fee
        );

        if (EUROs.balanceOf(msg.sender) == 0) {
            borrowedEuros = 0;
        }

        emit VaultifyEvents.EUROsBurned(_amount - fee, fee);
    }

    /**
     * @notice Retrieves the swap address for a given token symbol.
     * @param _symbol The symbol of the token.
     * @return The address of the token or the WETH address if the token address is zero.
     */
    function getSwapAddressFor(bytes32 _symbol) private view returns (address) {
        VaultifyStructs.Token memory _token = getToken(_symbol);
        return
            _token.addr == address(0) ? smartVaultManager.weth() : _token.addr;
    }

    /**
     * @notice Determines if a certain amount of collateral can be removed without under-collateralizing the vault.
     * @param _token The token information.
     * @param _amount The amount of collateral to remove.
     * @return True if the collateral can be removed, otherwise false.
     */
    function canRemoveCollateral(
        VaultifyStructs.Token memory _token,
        uint256 _amount
    ) private view returns (bool) {
        // If the user didn't borrow any EUROS yet then return true to remove his collateral.
        if (borrowedEuros == 0) return true;

        // The Maximum amount of EUROS to mint based on the collateral held in the vault.
        uint256 currentBorrowedEuros = calculateMaxBorrowableEuros();

        // The avg rpiv in EUROS of the amount of token to remove from the vault
        uint256 euroValueToRemove = calculator.tokenToEuroAvg(_token, _amount);

        // Ensures that the minted amount of minted EURO in the vault still backed by collateral after removing some collateral.
        // After removal, the remaining collateral must covers the already borrowed Euros.
        return
            currentBorrowedEuros >= euroValueToRemove &&
            borrowedEuros <= currentBorrowedEuros - euroValueToRemove;
    }

    /**
     * @notice Removes a specified amount of native currency collateral from the vault.
     * @param _amount The amount of native currency to remove.
     * @param _to The address to send the removed collateral to.
     */
    function removeNativeCollateral(
        uint256 _amount,
        address payable _to
    ) external onlyVaultOwner {
        bool canRemoveNative = canRemoveCollateral(getToken(NATIVE), _amount);
        uint256 vaultEthBal = address(this).balance;

        if (!canRemoveNative) revert VaultifyErrors.NativeRemove_Err();
        if (_amount > vaultEthBal) revert VaultifyErrors.NotEnoughEthBalance();
        if (_amount <= 0) revert VaultifyErrors.ZeroValue();
        if (_to == address(0)) revert VaultifyErrors.ZeroAddress();

        (bool succ, ) = _to.call{value: _amount}("");
        if (!succ) revert VaultifyErrors.NativeTxFailed();

        emit VaultifyEvents.NativeCollateralRemoved(NATIVE, _amount, _to);
    }

    /**
     * @notice Removes a specified amount of ERC20 token collateral from the vault.
     * @param _symbol The symbol of the token.
     * @param _amount The amount of token to remove.
     * @param _to The address to send the removed collateral to.
     */
    function removeERC20Collateral(
        bytes32 _symbol,
        uint256 _amount,
        address _to
    ) external onlyVaultOwner {
        VaultifyStructs.Token memory _token = getToken(_symbol);
        uint256 vaultTokenBal = IERC20(_token.addr).balanceOf(address(this));

        bool canRemoveERC20 = canRemoveCollateral(_token, _amount);

        if (!canRemoveERC20) revert VaultifyErrors.TokenRemove_Err();
        if (_amount <= 0) revert VaultifyErrors.ZeroValue();
        if (_to == address(0)) revert VaultifyErrors.ZeroAddress();
        if (_amount > vaultTokenBal)
            revert VaultifyErrors.NotEnoughTokenBalance();

        IERC20(_token.addr).safeTransfer(_to, _amount);

        emit VaultifyEvents.ERC20CollateralRemoved(_symbol, _amount, _to);
    }

    /**
     * @notice Executes a swap of native currency and deducts the swap fee.
     * @param _params The parameters for the swap.
     * @param _swapFee The fee for the swap.
     * @return amountOut The amount received from the swap.
     */
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

    /**
     * @notice Executes a swap of ERC20 tokens and deducts the swap fee.
     * @param _params The parameters for the swap.
     * @param _swapFee The fee for the swap.
     * @return amountOut The amount received from the swap.
     */
    function executeERC20SwapAndFee(
        ISwapRouter.ExactInputSingleParams memory _params,
        uint256 _swapFee
    ) private returns (uint256 amountOut) {
        // Send fees to liquidator
        IERC20(_params.tokenIn).safeTransfer(
            smartVaultManager.liquidator(),
            _swapFee
        );

        // //@audit todo Check the difference between forceApprove and increaseallowance?
        // approve the router to spend amountin on the vault behalf to conduct the swap
        // @audit check forceApprove vs approve
        IERC20(_params.tokenIn).forceApprove(
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
    // amountOutMinimum is used to specify the minimum amount of tokens
    // the caller wants to be returned from a swap
    /**
     * @notice Swaps a specified amount of one token for another.
     * @param _inTokenSymbol The symbol of the input token.
     * @param _outTokenSymbol The symbol of the output token.
     * @param _amount The amount of the input token to swap.
     * @param _minAmountOut The minimum amount out expected from the swap.
     */
    // TODO: Add dynamic price in the excuteSingle function in SwapRouterMock using the calculator
    // to mock a swap.
    function swap(
        bytes32 _inTokenSymbol,
        bytes32 _outTokenSymbol,
        uint256 _amount,
        uint24 _fee,
        uint256 _minAmountOut
    ) external onlyVaultOwner {
        // Calculate the fee swap
        uint256 swapFee = (_amount * smartVaultManager.swapFeeRate()) /
            smartVaultManager.HUNDRED_PRC();

        if (_amount == 0) revert VaultifyErrors.ZeroValue();

        address inToken = getSwapAddressFor(_inTokenSymbol);

        uint256 minimumAmountOut = calculateMinimimAmountOut(
            _inTokenSymbol,
            _outTokenSymbol,
            _amount,
            _minAmountOut
        );

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: inToken,
                tokenOut: getSwapAddressFor(_outTokenSymbol),
                fee: _fee,
                recipient: address(this),
                deadline: block.timestamp + 60, // 1 minute from now
                amountIn: _amount - swapFee,
                amountOutMinimum: minimumAmountOut,
                sqrtPriceLimitX96: 0
            });

        inToken == smartVaultManager.weth()
            ? executeNativeSwapAndFee(params, swapFee)
            : executeERC20SwapAndFee(params, swapFee);
    }

    /**
     * @notice Sets a new owner for the vault.
     * @param _newOwner The address of the new owner.
     */
    function setOwner(address _newOwner) external onlyVaultManager {
        owner = _newOwner;
    }
}
