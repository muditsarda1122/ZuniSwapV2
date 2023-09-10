//SPDX-License-Identifier
pragma solidity ^0.8.10;

import "../lib/solmate/src/tokens/ERC20.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";
import "./Interface/IZuniSwapV2Callee.sol";

interface IERC20 {
    function balanceOf(address) external returns (uint256);

    function transfer(address to, uint256 amount) external;
}

error AlreadyInitialized();
error InsufficientLiquidityMinted();
error InsufficientLiquidityBurned();
error InsufficientInputAmount();
error InsufficientOutputAmount();
error InsufficientLiquidity();
error InvalidConstantProductCheck();
error BalanceOverflow();
error TransferFailed();
error InvalidK();

contract ZuniSwapV2Pair is ERC20, Math {
    using UQ112x112 for uint224;
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private BlockTimeStampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    bool private isEntered;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserve0, uint256 reserve1);
    event Swap(
        address indexed sender,
        uint256 outputAmount0_,
        uint256 outputAmount1_,
        address indexed to
    );

    modifier nonReentrant() {
        require(!isEntered);
        isEntered = true;

        _;

        isEntered = false;
    }

    constructor(
        address _token0,
        address _token1
    ) ERC20("ZuniSwapV2", "ZUNIV2", 18) {
        token0 = _token0;
        token1 = _token1;
    }

    function initialize(address token0_, address token1_) public {
        if (token0 != address(0) || token1 != address(1)) {
            revert AlreadyInitialized();
        }

        token0 = token0_;
        token1 = token1_;
    }

    function mint() public {
        (uint112 reserve0_, uint112 reserve1_, ) = getReserves();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - reserve0_;
        uint256 amount1 = balance1 - reserve1_;

        uint256 liquidity;

        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * totalSupply) / reserve0_,
                (amount1 * totalSupply) / reserve1_
            );
        }

        if (liquidity <= 0) revert InsufficientLiquidityMinted();

        _mint(msg.sender, liquidity);

        _update(balance0, balance1, reserve0_, reserve1_);

        emit Mint(msg.sender, amount0, amount1);
    }

    function burn() public {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint liquidity = balanceOf[msg.sender];

        uint256 amount0 = (balance0 * liquidity) / totalSupply;
        uint256 amount1 = (balance1 * liquidity) / totalSupply;

        if (amount0 <= 0 || amount1 <= 0) revert InsufficientLiquidityBurned();

        _burn(msg.sender, liquidity);

        _safeTransfer(token0, msg.sender, amount0);
        _safeTransfer(token1, msg.sender, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        (uint112 reserve0_, uint112 reserve1_, ) = getReserves();
        _update(balance0, balance1, reserve0_, reserve1_);

        emit Burn(msg.sender, amount0, amount1);
    }

    function swap(
        uint256 outputAmount0,
        uint256 outputAmount1,
        address to,
        bytes calldata data
    ) public nonReentrant {
        if (outputAmount0 == 0 && outputAmount1 == 0) {
            revert InsufficientOutputAmount();
        }

        (uint112 reserve0_, uint112 reserve1_, ) = getReserves();

        if (outputAmount0 > reserve0_ || outputAmount1 > reserve1_) {
            revert InsufficientLiquidity();
        }

        if (outputAmount0 > 0) _safeTransfer(token0, to, outputAmount0);
        if (outputAmount1 > 0) _safeTransfer(token1, to, outputAmount1);
        if (data.length > 0)
            IZuniswapV2Callee(to).zuniswapV2Call(
                msg.sender,
                outputAmount0,
                outputAmount1,
                data
            );

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > reserve0 - outputAmount0
            ? balance0 - (reserve0 - outputAmount0)
            : 0;
        uint256 amount1In = balance1 > reserve1 - outputAmount1
            ? balance1 - (reserve1 - outputAmount1)
            : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);

        if (
            balance0Adjusted * balance1Adjusted <
            uint256(reserve0_) * uint256(reserve1_) * (1000 ** 2)
        ) revert InvalidK();

        _update(balance0, balance1, reserve0_, reserve1_);

        emit Swap(msg.sender, outputAmount0, outputAmount1, to);

        // uint256 balance0 = IERC20(token0).balanceOf(address(this)) -
        //     outputAmount0;
        // uint256 balance1 = IERC20(token1).balanceOf(address(this)) -
        //     outputAmount1;

        // /* If the below check holds then
        //    1. The caller has calculated the exchange rate correctly (including slippage)
        //    2. The output amount is correct
        //    3. The amount transferred to the contract is also correct
        // */
        // if (balance0 * balance1 < uint256(reserve0_) * uint256(reserve1_)) {
        //     revert InvalidConstantProductCheck();
        // }

        // _update(balance0, balance1, reserve0_, reserve1_);

        // if (outputAmount0 > 0) {
        //     _safeTransfer(token0, to, outputAmount0);
        // }
        // if (outputAmount1 > 0) {
        //     _safeTransfer(token1, to, outputAmount1);
        // }

        // emit Swap(msg.sender, outputAmount0, outputAmount1, to);
    }

    function sync() public {
        (uint112 reserve0_, uint112 reserve1_, ) = getReserves();
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0_,
            reserve1_
        );
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, BlockTimeStampLast);
    }

    ///////////////////
    // private ////////
    ///////////////////

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 reserve0_,
        uint112 reserve1_
    ) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert BalanceOverflow();
        }

        unchecked {
            uint32 timeElapsed = uint32(block.timestamp) - BlockTimeStampLast;

            if (timeElapsed > 0 && reserve0_ > 0 && reserve1_ > 0) {
                price0CumulativeLast +=
                    uint256(UQ112x112.encode(reserve1_).uqdiv(reserve0_)) *
                    timeElapsed;
                price1CumulativeLast +=
                    uint256(UQ112x112.encode(reserve0_).uqdiv(reserve1_)) *
                    timeElapsed;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        BlockTimeStampLast = uint32(block.timestamp);

        emit Sync(reserve0, reserve1);
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, value)
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool))))
            revert TransferFailed();
    }
}
