//SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

import "./Interface/IZuniSwapV2Factory.sol";
import "./Interface/IZuniSwapV2Pair.sol";
import "./ZuniSwapV2Library.sol";

contract ZuniSwapV2Router {
    error InsufficientAAmount();
    error InsufficientBAmount();
    error SafeTransferFailed();
    error excessiveInputAmount();
    error InsufficientOutputAmount();

    IZuniSwapV2Factory factory;

    constructor(address factoryAddress) {
        factory = IZuniSwapV2Factory(factoryAddress);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (factory.pairs(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB);
        }

        (amountA, amountB) = _calculateLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        address pairAddress = ZuniSwapV2Library.pairFor(
            address(factory),
            tokenA,
            tokenB
        );

        _safeTransferFrom(tokenA, msg.sender, pairAddress, amountA);
        _safeTransferFrom(tokenB, msg.sender, pairAddress, amountB);
        liquidity = IZuniSwapV2Pair(pairAddress).mint(to);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) public returns (uint256 amountA, uint256 amountB) {
        address pair = ZuniSwapV2Library.pairFor(
            address(factory),
            tokenA,
            tokenB
        );

        IZuniSwapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountA, amountB) = IZuniSwapV2Pair(pair).burn(to);

        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountB < amountBMin) revert InsufficientBAmount();
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) public returns (uint256[] memory amounts) {
        amounts = ZuniSwapV2Library.getAmountsOut(
            address(factory),
            amountIn,
            path
        );

        if (amounts[amounts.length - 1] < amountOutMin)
            revert InsufficientOutputAmount();

        _safeTransferFrom(
            path[0],
            msg.sender,
            ZuniSwapV2Library.pairFor(address(factory), path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to
    ) public returns (uint256[] memory amounts) {
        amounts = ZuniSwapV2Library.getAmountsIn(
            address(factory),
            amountOut,
            path
        );

        if (amounts[amounts.length - 1] > amountInMax)
            revert excessiveInputAmount();
        _safeTransferFrom(
            path[0],
            msg.sender,
            ZuniSwapV2Library.pairFor(address(factory), path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, to);
    }

    /////////////////////
    // private         //
    /////////////////////

    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = ZuniSwapV2Library.sortTokens(input, output);

            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            address to = i < path.length - 2
                ? ZuniSwapV2Library.pairFor(
                    address(factory),
                    output,
                    path[i + 2]
                )
                : _to;

            IZuniSwapV2Pair(
                ZuniSwapV2Library.pairFor(address(factory), input, output)
            ).swap(amount0Out, amount1Out, to, "");
        }
    }

    function _calculateLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = ZuniSwapV2Library.getReserves(
            address(factory),
            tokenA,
            tokenB
        );

        //as the reserves are 0, we can set the reserve ratio thus we are allowed to deposit whole amount
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = ZuniSwapV2Library.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal <= amountBMin) revert InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = ZuniSwapV2Library.quote(
                    amountBDesired,
                    reserveA,
                    reserveB
                );
                assert(amountAOptimal <= amountADesired);

                if (amountAOptimal <= amountAMin) revert InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                from,
                to,
                value
            )
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool))))
            revert SafeTransferFailed();
    }
}
