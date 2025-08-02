## TWAP (Time-Weighted Average Price) Architecture for 1inch Limit Order Protocol

# Adaptive TWAP Strategy / Continous Time-Weighted Average Price

CTWAPStrategy extends 1inch Limit Order Protocol with a volatility-aware TWAP: it schedules chunked execution, gates fills with Chainlink-based realized volatility and price-feed safety checks, enforces price-impact ceilings, and adaptively sizes chunks—fully on-chain, no official API required



This implementation enhances traditional TWAP logic by introducing:

Volatility-aware chunk sizing

Chainlink oracle integrations

Batched multi-order execution support for relayers

The goal is to maximize execution efficiency, minimize slippage, and provide a safe and programmable experience for both users and resolvers.

# Features

 1. TWAP Execution Logic.

 2. Volatility-Aware Chunk Sizing (via Chainlink).

 3. Gas-Aware Deferment
 
 4. Batched Multi-TWAP Execution

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
