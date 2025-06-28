// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SimpleSwap - Minimal AMM for a fixed token pair with LP tokens (gas optimized)
/// @notice Add/remove liquidity, swap tokens, get prices, calculate amounts out
contract SimpleSwap is ERC20 {
    using SafeERC20 for IERC20;

    address public immutable tokenA;
    address public immutable tokenB;

    uint112 private reserveA;
    uint112 private reserveB;

    uint private constant FEE_NUMERATOR = 997;
    uint private constant FEE_DENOMINATOR = 1000;

    event LiquidityAdded(address indexed user, uint amountA, uint amountB, uint liquidity);
    event LiquidityRemoved(address indexed user, uint amountA, uint amountB, uint liquidity);
    event SwapExecuted(address indexed user, address tokenIn, address tokenOut, uint amountIn, uint amountOut);

    constructor(address _tokenA, address _tokenB) ERC20("SimpleSwap LP Token", "SSLP") {
        require(_tokenA != _tokenB, "Identical token addresses");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    /// @notice Add liquidity and mint LP tokens
    function addLiquidity(
        address to,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        require(block.timestamp <= deadline, "Expired");

        uint _reserveA = reserveA;
        uint _reserveB = reserveB;

        if (_reserveA == 0 && _reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint amountBOptimal = (amountADesired * _reserveB) / _reserveA;
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Slippage B");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint amountAOptimal = (amountBDesired * _reserveA) / _reserveB;
                require(amountAOptimal >= amountAMin, "Slippage A");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }

        // Transfer tokens in
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        // Calculate liquidity to mint
        if (totalSupply() == 0) {
            liquidity = sqrt(amountA * amountB);
        } else {
            liquidity = min(
                (amountA * totalSupply()) / _reserveA,
                (amountB * totalSupply()) / _reserveB
            );
        }
        require(liquidity > 0, "Insufficient liquidity");

        // Update reserves manually
        reserveA = uint112(_reserveA + amountA);
        reserveB = uint112(_reserveB + amountB);

        _mint(to, liquidity);

        emit LiquidityAdded(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Remove liquidity and burn LP tokens
    function removeLiquidity(
        address to,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        require(block.timestamp <= deadline, "Expired");
        require(liquidity > 0 && liquidity <= balanceOf(msg.sender), "Invalid liquidity");

        uint _totalSupply = totalSupply();

        amountA = (liquidity * reserveA) / _totalSupply;
        amountB = (liquidity * reserveB) / _totalSupply;

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage");

        _burn(msg.sender, liquidity);

        // Update reserves manually
        reserveA -= uint112(amountA);
        reserveB -= uint112(amountB);

        IERC20(tokenA).safeTransfer(to, amountA);
        IERC20(tokenB).safeTransfer(to, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Swap exact tokens for tokens with minimum output
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint deadline
    ) external returns (uint amountOut) {
        require(block.timestamp <= deadline, "Expired");
        require(
            (tokenIn == tokenA && tokenOut == tokenB) ||
            (tokenIn == tokenB && tokenOut == tokenA),
            "Invalid token pair"
        );
        require(amountIn > 0, "AmountIn zero");
        require(to != address(0), "Invalid recipient");

        bool zeroForOne = tokenIn == tokenA;
        (uint _reserveIn, uint _reserveOut) = zeroForOne ? (reserveA, reserveB) : (reserveB, reserveA);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate amount out with fee
        amountOut = getAmountOut(amountIn, _reserveIn, _reserveOut);
        require(amountOut >= amountOutMin, "Insufficient output");

        IERC20(tokenOut).safeTransfer(to, amountOut);

        // Update reserves manually
        if (zeroForOne) {
            reserveA = uint112(_reserveIn + amountIn);
            reserveB = uint112(_reserveOut - amountOut);
        } else {
            reserveB = uint112(_reserveIn + amountIn);
            reserveA = uint112(_reserveOut - amountOut);
        }

        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Returns price of base token in terms of quote token scaled by 1e18
    function getPrice(address base, address quote) external view returns (uint price) {
        require(
            (base == tokenA && quote == tokenB) ||
            (base == tokenB && quote == tokenA),
            "Invalid pair"
        );

        if (base == tokenA) {
            price = (uint(reserveB) * 1e18) / reserveA;
        } else {
            price = (uint(reserveA) * 1e18) / reserveB;
        }
    }

    /// @notice Calculate amount out for given amount in and reserves with fee
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "Invalid inputs");
        uint amountInWithFee = amountIn * FEE_NUMERATOR;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Babylonian method for square root
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @notice Returns min between two uints
    function min(uint x, uint y) internal pure returns (uint) {
        return x < y ? x : y;
    }
}

