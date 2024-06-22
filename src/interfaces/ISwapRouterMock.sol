// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ISwapRouterMock {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
        uint256 txValue;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);

    function receivedSwap()
        external
        view
        returns (ExactInputSingleParams memory);
}
