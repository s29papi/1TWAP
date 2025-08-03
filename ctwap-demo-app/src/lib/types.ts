// Data types and interfaces for CTWAP protocol

export interface CreateOrderParams {
    makerAsset: string
    takerAsset: string
    makingAmount: string
    takingAmount: string
    volatilityThreshold: number
    chunkInterval: number
    totalChunks: number
    minChunkSize: string
  }
  
  export interface OrderStatus {
    orderHash: string
    canExecute: boolean
    reason: string
    currentVolatility: number
    executedChunks: number
    totalChunks: number
    lastExecutionTime: number
    totalMakingAmount: string
    totalTakingAmount: string
    isActive: boolean
  }
  
  export interface VolatilityData {
    timestamp: number
    volatility: number
    price: number
  }
  
  export interface LogEntry {
    id: string
    timestamp: Date
    type: 'info' | 'success' | 'warning' | 'error'
    message: string
    txHash?: string
    blockNumber?: number
  }
  
  export interface Token {
    address: string
    symbol: string
    name: string
    decimals: number
    logoURI: string
  }
  
  export interface OrderDetails {
    orderHash: string
    status: 'active' | 'completed' | 'cancelled'
    fromToken: Token
    toToken: Token
    fromAmount: string
    toAmount: string
    strategyType: string
    chunks: {
      total: number
      executed: number
    }
    createdAt: Date
    settings: {
      volatilityThreshold: number
      chunkInterval: number
      minChunkSize: string
    }
  }