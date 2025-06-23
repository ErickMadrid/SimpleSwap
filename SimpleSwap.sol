// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SimpleSwap - Optimized AMM for token swapping
/// @author
/// @notice Provides basic liquidity and swapping functions like Uniswap
contract SimpleSwap is ERC20 {
    using SafeERC20 for IERC20;

    address public immutable tokenA;
    address public immutable tokenB;

    uint112 private reserveA; // Using uint112 like Uniswap for gas efficiency
    uint112 private reserveB;

    uint private constant FEE_NUMERATOR = 997;
    uint private constant FEE_DENOMINATOR = 1000;

    constructor(address _tokenA, address _tokenB) ERC20("SimpleSwap LP Token", "SSLP") {
        require(_tokenA != _tokenB, "Identical addresses");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function _updateReserves(uint balanceA, uint balanceB) private {
        reserveA = uint112(balanceA);
        reserveB = uint112(balanceB);
    }

    function addLiquidity(
        address to,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        require(block.timestamp <= deadline, "Expired");

        (uint _reserveA, uint _reserveB) = (reserveA, reserveB);

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

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));

        if (totalSupply() == 0) {
            liquidity = sqrt(amountA * amountB);
        } else {
            liquidity = min(
                (amountA * totalSupply()) / _reserveA,
                (amountB * totalSupply()) / _reserveB
            );
        }
        require(liquidity > 0, "Insufficient liquidity");

        _mint(to, liquidity);
        _updateReserves(balanceA, balanceB);
    }

    function removeLiquidity(
        address to,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        require(block.timestamp <= deadline, "Expired");

        uint _totalSupply = totalSupply();
        amountA = (liquidity * reserveA) / _totalSupply;
        amountB = (liquidity * reserveB) / _totalSupply;

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage");

        _burn(msg.sender, liquidity);

        IERC20(tokenA).safeTransfer(to, amountA);
        IERC20(tokenB).safeTransfer(to, amountB);

        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));
        _updateReserves(balanceA, balanceB);
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address input,
        address output,
        address to,
        uint deadline
    ) external returns (uint amountOut) {
        require(block.timestamp <= deadline, "Expired");
        require((input == tokenA && output == tokenB) || (input == tokenB && output == tokenA), "Invalid tokens");

        bool zeroForOne = input == tokenA;
        (uint reserveIn, uint reserveOut) = zeroForOne ? (reserveA, reserveB) : (reserveB, reserveA);

        IERC20(input).safeTransferFrom(msg.sender, address(this), amountIn);
        uint balanceIn = IERC20(input).balanceOf(address(this));
        uint actualIn = balanceIn - reserveIn;

        amountOut = getAmountOut(actualIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Insufficient output");

        IERC20(output).safeTransfer(to, amountOut);

        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));
        _updateReserves(balanceA, balanceB);
    }

    function getPrice(address base, address quote) external view returns (uint price) {
        require((base == tokenA && quote == tokenB) || (base == tokenB && quote == tokenA), "Invalid tokens");
        if (base == tokenA) {
            price = (uint(reserveB) * 1e18) / reserveA;
        } else {
            price = (uint(reserveA) * 1e18) / reserveB;
        }
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        uint amountInWithFee = amountIn * FEE_NUMERATOR;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function min(uint x, uint y) private pure returns (uint) {
        return x < y ? x : y;
    }

    function sqrt(uint y) private pure returns (uint z) {
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
}
