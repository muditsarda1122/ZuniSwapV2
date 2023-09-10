// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

interface IZuniswapV2Callee {
    // this is the function that the callee will let the caller call for which the loan was taken
    // validation that the loan was repaid in the same transaction is that new value of 'k' is getting checked
    function zuniswapV2Call(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external;
}
