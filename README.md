# SimpleSwap

`SimpleSwap` is a gas-efficient, minimalistic automated market maker (AMM) smart contract inspired by Uniswap v2. It allows users to:

- Add/remove liquidity to a token pair
- Swap between two ERC-20 tokens
- Get token prices and expected output amounts

## Features

- ✅ ERC-20 support (fee-on-transfer compatible)
- ⚡ Gas-efficient reserve storage (uint112)
- 💧 LP tokens for liquidity providers
- 🔒 Slippage and deadline protections

## Functions

### `addLiquidity(...)`
Adds tokens to the pool. Issues LP tokens to the user.

### `removeLiquidity(...)`
Burns LP tokens and returns the underlying tokens.

### `swapExactTokensForTokens(...)`
Swaps one token for another with fee and slippage handling.

### `getPrice(...)`
Returns the current price of one token in terms of another.

### `getAmountOut(...)`
Computes expected output amount given an input amount.

## Example Usage

```solidity
// Add liquidity
simpleSwap.addLiquidity(to, 1e18, 2e18, 0.9e18, 1.9e18, deadline);

// Swap tokenA for tokenB
simpleSwap.swapExactTokensForTokens(1e18, 0.9e18, tokenA, tokenB, to, deadline);

// Get price
uint price = simpleSwap.getPrice(tokenA, tokenB);

// Estimate output
uint out = simpleSwap.getAmountOut(1e18, reserveA, reserveB);
