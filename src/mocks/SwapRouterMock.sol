// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "src/interfaces/ISwapRouter.sol";
import "src/interfaces/ISwapRouterMock.sol";

contract SwapRouterMock is ISwapRouter {
    address private tokenIn;
    address private tokenOut;
    uint24 public fee;
    address private recipient;
    uint256 private deadline;
    uint256 private amountIn;
    uint256 private amountOutMinimum;
    uint160 private sqrtPriceLimitX96;
    uint256 private txValue;

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut) {
        tokenIn = params.tokenIn;
        tokenOut = params.tokenOut;
        fee = params.fee;
        recipient = params.recipient;
        deadline = params.deadline;
        amountIn = params.amountIn;
        amountOutMinimum = params.amountOutMinimum;
        sqrtPriceLimitX96 = params.sqrtPriceLimitX96;
        txValue = msg.value;
    }

    function receivedSwap() external view returns (MockSwapData memory) {
        return
            MockSwapData(
                tokenIn,
                tokenOut,
                fee,
                recipient,
                deadline,
                amountIn,
                amountOutMinimum,
                sqrtPriceLimitX96,
                txValue
            );
    }
}
