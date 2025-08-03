// Mock data generators for testing
import { VolatilityData, LogEntry, OrderDetails } from './types'
import { TOKENS } from './contracts'

export function generateMockVolatilityData(points: number = 20): VolatilityData[] {
  const data: VolatilityData[] = []
  const now = Date.now()
  
  for (let i = 0; i < points; i++) {
    data.push({
      timestamp: now - (points - i) * 60000,
      volatility: 2000 + Math.random() * 4000 + Math.sin(i / 3) * 1500,
      price: 3400 + Math.random() * 100
    })
  }
  
  return data
}

export function generateMockLogs(): LogEntry[] {
  return [
    {
      id: '1',
      timestamp: new Date(Date.now() - 300000),
      type: 'success',
      message: 'Chunk executed successfully',
      txHash: '0x123...abc',
      blockNumber: 12345678
    },
    {
      id: '2',
      timestamp: new Date(Date.now() - 600000),
      type: 'info',
      message: 'Volatility within threshold, chunk ready',
    },
    {
      id: '3',
      timestamp: new Date(Date.now() - 900000),
      type: 'warning',
      message: 'High volatility detected, execution paused',
    },
    {
      id: '4',
      timestamp: new Date(Date.now() - 1200000),
      type: 'success',
      message: 'Order created and monitoring started',
      txHash: '0xdef...456',
      blockNumber: 12345670
    }
  ]
}

export function generateMockOrderDetails(): OrderDetails {
  return {
    orderHash: '0x123...abc',
    status: 'active',
    fromToken: TOKENS.USDC,
    toToken: TOKENS.WETH,
    fromAmount: '1000000000',
    toAmount: '294000000000000000',
    strategyType: 'CTWAP',
    chunks: {
      total: 4,
      executed: 2
    },
    createdAt: new Date(Date.now() - 1800000),
    settings: {
      volatilityThreshold: 50,
      chunkInterval: 300,
      minChunkSize: '250000000'
    }
  }
}