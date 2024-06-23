// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ISwapRouterMock {
    struct MockSwapData {
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

    // function exactInputSingle(
    //     MockSwapData calldata params
    // ) external payable returns (uint256 amountOut);

    function receivedSwap() external view returns (MockSwapData memory);
}
