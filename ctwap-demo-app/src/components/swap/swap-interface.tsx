'use client'

import { useState } from 'react'
import { ArrowsUpDownIcon, ChevronDownIcon, ExclamationTriangleIcon } from '@heroicons/react/24/outline'
import { Button } from '@/src/components/ui/button'
import { Input } from '@/src/components/ui/input'
import { Card, CardContent, CardHeader, CardTitle } from '@/src/components/ui/card'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/src/components/ui/collapsible'
import { TOKENS } from '@/src/lib/contracts'

export default function SwapInterface() {
  const [fromAmount, setFromAmount] = useState('')
  const [toAmount, setToAmount] = useState('')
  const [fromToken, setFromToken] = useState(TOKENS.USDC)
  const [toToken, setToToken] = useState(TOKENS.WETH)
  
  // CTWAP Settings
  const [maxVolatility, setMaxVolatility] = useState(50)
  const [minChunkSize, setMinChunkSize] = useState(25)
  const [interval, setInterval] = useState(300)
  const [settingsOpen, setSettingsOpen] = useState(false)

  const calculatedChunks = minChunkSize > 0 ? Math.ceil(100 / minChunkSize) : 0

  const handleSwapTokens = () => {
    setFromToken(toToken)
    setToToken(fromToken)
    setFromAmount(toAmount)
    setToAmount(fromAmount)
  }

  const handleCreateOrder = () => {
    // Mock order creation
    console.log('Creating CTWAP order...', {
      fromAmount,
      toAmount,
      fromToken,
      toToken,
      maxVolatility,
      minChunkSize,
      interval
    })
  }

  return (
    <div className="space-y-4">
      <Card className="bg-gray-900 border-gray-800">
        <CardHeader>
          <CardTitle className="text-white">Swap</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* From Token */}
          <div className="space-y-2">
            <label className="text-sm text-gray-400">From</label>
            <div className="flex space-x-2">
              <div className="flex-1">
                <Input
                  value={fromAmount}
                  onChange={(e) => setFromAmount(e.target.value)}
                  placeholder="0.0"
                  className="bg-gray-800 border-gray-700 text-white text-lg"
                />
              </div>
              <button className="flex items-center space-x-2 bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 hover:bg-gray-700">
                <img src={fromToken.logoURI} alt={fromToken.symbol} className="w-5 h-5" />
                <span className="text-white font-medium">{fromToken.symbol}</span>
                <ChevronDownIcon className="h-4 w-4 text-gray-400" />
              </button>
            </div>
            <div className="text-xs text-gray-500">Balance: 1,234.56 {fromToken.symbol}</div>
          </div>

          {/* Swap Direction */}
          <div className="flex justify-center">
            <button
              onClick={handleSwapTokens}
              className="p-2 bg-gray-800 border border-gray-700 rounded-lg hover:bg-gray-700 transition-colors"
            >
              <ArrowsUpDownIcon className="h-5 w-5 text-gray-400" />
            </button>
          </div>

          {/* To Token */}
          <div className="space-y-2">
            <label className="text-sm text-gray-400">To</label>
            <div className="flex space-x-2">
              <div className="flex-1">
                <Input
                  value={toAmount}
                  onChange={(e) => setToAmount(e.target.value)}
                  placeholder="0.0"
                  className="bg-gray-800 border-gray-700 text-white text-lg"
                />
              </div>
              <button className="flex items-center space-x-2 bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 hover:bg-gray-700">
                <img src={toToken.logoURI} alt={toToken.symbol} className="w-5 h-5" />
                <span className="text-white font-medium">{toToken.symbol}</span>
                <ChevronDownIcon className="h-4 w-4 text-gray-400" />
              </button>
            </div>
            <div className="text-xs text-gray-500">Balance: 0.543 {toToken.symbol}</div>
          </div>
        </CardContent>
      </Card>

      {/* CTWAP Settings */}
      <Card className="bg-gray-900 border-gray-800">
        <Collapsible open={settingsOpen} onOpenChange={setSettingsOpen}>
          <CollapsibleTrigger asChild>
            <CardHeader className="cursor-pointer hover:bg-gray-800/50">
              <CardTitle className="flex items-center justify-between text-white">
                CTWAP Settings
                <ChevronDownIcon className={`h-5 w-5 text-gray-400 transition-transform ${settingsOpen ? 'rotate-180' : ''}`} />
              </CardTitle>
            </CardHeader>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <label className="text-sm text-gray-400">Max Volatility %</label>
                  <Input
                    type="number"
                    value={maxVolatility}
                    onChange={(e) => setMaxVolatility(Number(e.target.value))}
                    className="bg-gray-800 border-gray-700 text-white"
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-sm text-gray-400">Min Chunk Size %</label>
                  <Input
                    type="number"
                    value={minChunkSize}
                    onChange={(e) => setMinChunkSize(Number(e.target.value))}
                    className="bg-gray-800 border-gray-700 text-white"
                  />
                </div>
              </div>
              <div className="space-y-2">
                <label className="text-sm text-gray-400">Interval (seconds)</label>
                <Input
                  type="number"
                  value={interval}
                  onChange={(e) => setInterval(Number(e.target.value))}
                  className="bg-gray-800 border-gray-700 text-white"
                />
              </div>
              <div className="bg-gray-800 rounded-lg p-3">
                <div className="text-sm text-gray-400">Calculated Chunks: <span className="text-white font-medium">{calculatedChunks}</span></div>
              </div>
            </CardContent>
          </CollapsibleContent>
        </Collapsible>
      </Card>

      {/* Price Info */}
      <Card className="bg-gray-900 border-gray-800">
        <CardContent className="pt-6">
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-gray-400">Expected Price</span>
              <span className="text-white">1 USDC = 0.000294 ETH</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Price Impact</span>
              <span className="text-green-400">0.12%</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Network Fee</span>
              <span className="text-white">~$2.43</span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Warning Box */}
      <div className="bg-yellow-900/20 border border-yellow-700 rounded-lg p-4">
        <div className="flex items-start space-x-3">
          <ExclamationTriangleIcon className="h-5 w-5 text-yellow-500 mt-0.5" />
          <div className="text-sm text-yellow-200">
            CTWAP orders execute in chunks based on market volatility. Order may not complete immediately.
          </div>
        </div>
      </div>

      {/* Action Button */}
      <Button
        onClick={handleCreateOrder}
        className="w-full bg-pink-600 hover:bg-pink-700 text-white py-3 text-lg font-medium"
        disabled={!fromAmount || !toAmount}
      >
        Create CTWAP Order
      </Button>
    </div>
  )
}