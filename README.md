# Continuous Time-Weighted Average Price (CTWAPStrategy)
CTWAPStrategy is an advanced on-chain strategy that extends the 1inch Limit Order Protocol with volatility-aware TWAP execution—all without relying on the official 1inch API.

It automates chunked order execution, dynamically sizes each chunk based on market volatility (using Chainlink oracles), enforces robust price-impact protections, and continuously validates price feeds for safety. All strategy logic runs fully on-chain and can be used by anyone building or settling limit orders.

## Key Features
TWAP Execution:
Schedule and execute large trades as smaller “chunks” over time to minimize market impact.

Volatility-Aware Chunk Sizing:
Each chunk’s size is adaptively calculated using realized volatility derived from Chainlink oracles, reducing risk during turbulent market conditions.

On-Chain Oracle Integration:
Integrates Chainlink price feeds for real-time market data and robust price-feed safety checks.

Price Impact Protections:
Ensures no single chunk execution exceeds user-defined slippage or price impact ceilings.

No Official API Required:
Works natively with 1inch Limit Order Protocol smart contracts—no need for off-chain coordination or the 1inch API.

Programmable & Secure:
Provides a highly customizable and programmable TWAP interface for power users, market makers, and resolvers.

## Why CTWAPStrategy?
By combining time-weighted execution with on-chain volatility and safety checks, CTWAPStrategy aims to maximize execution efficiency and provide a transparent, programmable, and safer experience for both users and resolvers.

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
