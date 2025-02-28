# Distribution Markets

A prediction market protocol for trading on continuous outcome distributions.

## Overview

This protocol enables traders to express beliefs about continuous outcomes (like timing of events or price levels) through full probability distributions rather than just binary or discrete options. The implementation uses Gaussian distributions and a constant function market maker with L2 norm preservation.

## Features

- Trade on full probability distributions instead of discrete outcomes
- Specializes in Normal/Gaussian distributions with adjustable parameters
- Constant Function AMM with mathematical guarantees
- Permissionless liquidity provision
- Fully collateralized positions via NFTs

## Development

This project uses [Foundry](https://github.com/foundry-rs/foundry).

```shell
# Build the project
forge build

# Run tests
forge test

# Format code
forge fmt

# Generate gas snapshots
forge snapshot

# Local development node
anvil

# Deploy (replace with your values)
forge script script/Deploy.s.sol:DeployScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Basic Usage

```solidity
// Initialize a market
DistributionAMM market = new DistributionAMM();
market.initialize(
    4.47e17,  // k - L2 norm 
    1e18,     // b - backing amount
    4.47e17,  // kToBRatio
    1e18,     // sigma - initial std dev
    1e18,     // lambda - scale factor
    0,        // mu - initial mean
    1e17      // minSigma - minimum std dev
);

// Add liquidity
(shares, positionId) = market.addLiquidity(1e18);

// Trade to move the market
market.trade(
    1e18,    // collateral
    5e17,    // new mean
    1.2e18,  // new std dev 
    1e18,    // new scale factor
    -1e18    // critical point
);

// Resolve market and withdraw
market.resolve(6e17);  // outcome value
market.withdraw(positionId, 1e18);
```

## Architecture

- **DistributionAMM**: Handles trades, liquidity provision, and market resolution
- **PositionNFT**: Manages trader positions as NFTs with payout calculations
- **Math**: Utility library for Gaussian calculations and other mathematical operations

## References

This implementation is based on the concepts described in:
- White, D. (2024). [Distribution Markets](https://www.paradigm.xyz/blog/distribution-markets). Paradigm Research.

## License

MIT