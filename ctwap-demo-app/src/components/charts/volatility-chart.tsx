'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/src/components/ui/card'
import { generateMockVolatilityData } from '@/src/lib/mock-data'
import { formatVolatility, getVolatilityColor } from '@/src/lib/utils/formatter'
import type { VolatilityData } from '@/src/lib/types'

export default function VolatilityChart() {
  const [data, setData] = useState<VolatilityData[]>([])
  const [currentVolatility, setCurrentVolatility] = useState(0)

  useEffect(() => {
    // Initial data load
    const initialData = generateMockVolatilityData(20)
    setData(initialData)
    setCurrentVolatility(initialData[initialData.length - 1]?.volatility || 0)

    // Simulate real-time updates
    const interval = setInterval(() => {
      const newPoint: VolatilityData = {
        timestamp: Date.now(),
        volatility: 2000 + Math.random() * 4000 + Math.sin(Date.now() / 60000) * 1500,
        price: 3400 + Math.random() * 100
      }
      
      setData(prev => {
        const updated = [...prev.slice(1), newPoint]
        setCurrentVolatility(newPoint.volatility)
        return updated
      })
    }, 5000)

    return () => clearInterval(interval)
  }, [])

  const stats = {
    low: Math.min(...data.map(d => d.volatility)),
    average: data.reduce((sum, d) => sum + d.volatility, 0) / data.length,
    high: Math.max(...data.map(d => d.volatility))
  }

  const maxVolatility = Math.max(...data.map(d => d.volatility))

  return (
    <Card className="bg-gray-900 border-gray-800">
      <CardHeader>
        <CardTitle className="text-white">Market Volatility</CardTitle>
      </CardHeader>
      <CardContent>
        {/* Current Volatility Display */}
        <div className="mb-6 text-center">
          <div className="text-3xl font-bold" style={{ color: getVolatilityColor(currentVolatility) }}>
            {formatVolatility(currentVolatility)}
          </div>
          <div className="text-sm text-gray-400">Current Volatility</div>
        </div>

        {/* Simple Chart Visualization */}
        <div className="h-64 mb-4 bg-gray-800 rounded-lg p-4 relative overflow-hidden">
          <div className="absolute inset-0 p-4">
            {/* Grid lines */}
            <div className="absolute inset-4 opacity-20">
              {[0, 25, 50, 75, 100].map((percent) => (
                <div
                  key={percent}
                  className="absolute w-full border-t border-gray-600"
                  style={{ top: `${percent}%` }}
                />
              ))}
              {[0, 20, 40, 60, 80, 100].map((percent) => (
                <div
                  key={percent}
                  className="absolute h-full border-l border-gray-600"
                  style={{ left: `${percent}%` }}
                />
              ))}
            </div>
            
            {/* Chart line */}
            <svg className="w-full h-full" viewBox="0 0 400 200">
              <defs>
                <linearGradient id="volatilityGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                  <stop offset="0%" stopColor="#ec4899" stopOpacity="0.3" />
                  <stop offset="100%" stopColor="#ec4899" stopOpacity="0" />
                </linearGradient>
              </defs>
              
              {/* Chart area */}
              <path
                d={`M 0 ${200 - (data[0]?.volatility || 0) / maxVolatility * 180} ${data.map((point, index) => 
                  `L ${(index / (data.length - 1)) * 400} ${200 - (point.volatility / maxVolatility) * 180}`
                ).join(' ')}`}
                fill="none"
                stroke="#ec4899"
                strokeWidth="2"
                className="drop-shadow-sm"
              />
              
              {/* Fill area */}
              <path
                d={`M 0 200 L 0 ${200 - (data[0]?.volatility || 0) / maxVolatility * 180} ${data.map((point, index) => 
                  `L ${(index / (data.length - 1)) * 400} ${200 - (point.volatility / maxVolatility) * 180}`
                ).join(' ')} L 400 200 Z`}
                fill="url(#volatilityGradient)"
              />
              
              {/* Current point */}
              {data.length > 0 && (
                <circle
                  cx={400}
                  cy={200 - (currentVolatility / maxVolatility) * 180}
                  r="4"
                  fill="#ec4899"
                  stroke="#1f2937"
                  strokeWidth="2"
                  className="animate-pulse"
                />
              )}
              
              {/* Threshold line */}
              <line
                x1="0"
                y1={200 - (5000 / maxVolatility) * 180}
                x2="400"
                y2={200 - (5000 / maxVolatility) * 180}
                stroke="#ef4444"
                strokeWidth="1"
                strokeDasharray="5,5"
                opacity="0.7"
              />
            </svg>
            
            {/* Y-axis labels */}
            <div className="absolute left-0 top-0 h-full flex flex-col justify-between text-xs text-gray-400 -ml-12">
              <span>{formatVolatility(maxVolatility)}</span>
              <span>{formatVolatility(maxVolatility * 0.75)}</span>
              <span>{formatVolatility(maxVolatility * 0.5)}</span>
              <span>{formatVolatility(maxVolatility * 0.25)}</span>
              <span>0%</span>
            </div>
            
            {/* X-axis labels */}
            <div className="absolute bottom-0 left-0 w-full flex justify-between text-xs text-gray-400 -mb-6">
              <span>{new Date(data[0]?.timestamp || Date.now()).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}</span>
              <span>Now</span>
            </div>
          </div>
        </div>

        {/* Statistics */}
        <div className="grid grid-cols-3 gap-4 text-center">
          <div>
            <div className="text-lg font-semibold text-green-400">{formatVolatility(stats.low)}</div>
            <div className="text-xs text-gray-400">Low</div>
          </div>
          <div>
            <div className="text-lg font-semibold text-yellow-400">{formatVolatility(stats.average)}</div>
            <div className="text-xs text-gray-400">Average</div>
          </div>
          <div>
            <div className="text-lg font-semibold text-red-400">{formatVolatility(stats.high)}</div>
            <div className="text-xs text-gray-400">High</div>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}