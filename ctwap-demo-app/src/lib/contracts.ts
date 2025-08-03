// Contract addresses and constants for Base network
export const CONTRACTS = {
    CTWAP_STRATEGY: "0x302b2b6dced7f70b072be8ffacaa6a2cf882cae9", // Your deployed CTWAP strategy address
    LIMIT_ORDER_PROTOCOL: "0x111111125421cA6dc452d289314280a0f8842A65",
    WETH: "0x4200000000000000000000000000000000000006",
    USDC: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    ETH_USD_ORACLE: "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70"
  }
  
  export const CHAIN_ID = 8453 // Base mainnet
  
  // Token metadata
  export const TOKENS = {
    WETH: {
      address: CONTRACTS.WETH,
      symbol: "WETH",
      name: "Wrapped Ether",
      decimals: 18,
      logoURI: "https://ethereum-optimism.github.io/data/WETH/logo.png"
    },
    USDC: {
      address: CONTRACTS.USDC,
      symbol: "USDC",
      name: "USD Coin",
      decimals: 6,
      logoURI: "https://ethereum-optimism.github.io/data/USDC/logo.png"
    }
  }