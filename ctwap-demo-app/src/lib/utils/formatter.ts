// Utility functions for formatting data
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatTokenAmount(amount: string, decimals: number): string {
    return (Number(amount) / Math.pow(10, decimals)).toFixed(4)
  }
  
  export function calculatePrice(
    makingAmount: string,
    takingAmount: string,
    makerDecimals: number,
    takerDecimals: number
  ): number {
    const maker = Number(makingAmount) / Math.pow(10, makerDecimals)
    const taker = Number(takingAmount) / Math.pow(10, takerDecimals)
    return maker / taker
  }
  
  export function formatVolatility(volatilityBps: number): string {
    return (volatilityBps / 100).toFixed(2) + '%'
  }
  
  export function formatAddress(address: string): string {
    return `${address.slice(0, 6)}...${address.slice(-4)}`
  }
  
  export function formatTime(timestamp: number): string {
    return new Date(timestamp * 1000).toLocaleTimeString()
  }
  
  export function formatDate(date: Date): string {
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }
  
  export function getVolatilityColor(volatility: number): string {
    if (volatility < 3000) return '#10b981' // green
    if (volatility < 5000) return '#f59e0b' // yellow
    return '#ef4444' // red
  }