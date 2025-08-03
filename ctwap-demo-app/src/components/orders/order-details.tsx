'use client'

import { useState } from 'react'
import { ClipboardDocumentIcon, ArrowTopRightOnSquareIcon } from '@heroicons/react/24/outline'
import { Card, CardContent, CardHeader, CardTitle } from '@/src/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/src/components/ui/tabs'
import { Badge } from '@/src/components/ui/badge'
import { Button } from '@/src/components/ui/button'
import { generateMockOrderDetails, generateMockLogs } from '@/src/lib/mock-data'
import { formatAddress, formatDate, formatTokenAmount } from '@/src/lib/utils/formatter'
import toast from 'react-hot-toast'

export default function OrderDetails() {
  const [activeTab, setActiveTab] = useState('details')
  const [logFilter, setLogFilter] = useState('all')
  
  const orderDetails = generateMockOrderDetails()
  const logs = generateMockLogs()

  const copyOrderHash = () => {
    navigator.clipboard.writeText(orderDetails.orderHash)
    toast.success('Order hash copied to clipboard')
  }

  const filteredLogs = logs.filter(log => 
    logFilter === 'all' || log.type === logFilter
  )

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active': return 'bg-green-500'
      case 'completed': return 'bg-blue-500'
      case 'cancelled': return 'bg-red-500'
      default: return 'bg-gray-500'
    }
  }

  const getLogIcon = (type: string) => {
    switch (type) {
      case 'success': return '✅'
      case 'warning': return '⚠️'
      case 'error': return '❌'
      default: return 'ℹ️'
    }
  }

  return (
    <Card className="bg-gray-900 border-gray-800">
      <CardHeader>
        <CardTitle className="text-white">Order Details</CardTitle>
        
        {/* Order Hash */}
        <div className="flex items-center space-x-2 bg-gray-800 rounded-lg p-3">
          <span className="text-sm text-gray-400">Hash:</span>
          <span className="text-sm text-white font-mono">{formatAddress(orderDetails.orderHash)}</span>
          <Button
            variant="ghost"
            size="sm"
            onClick={copyOrderHash}
            className="p-1 h-auto text-gray-400 hover:text-white"
          >
            <ClipboardDocumentIcon className="h-4 w-4" />
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="p-1 h-auto text-gray-400 hover:text-white"
          >
            <ArrowTopRightOnSquareIcon className="h-4 w-4" />
          </Button>
        </div>
      </CardHeader>
      
      <CardContent>
        <Tabs value={activeTab} onValueChange={setActiveTab}>
          <TabsList className="grid w-full grid-cols-2 bg-gray-800">
            <TabsTrigger value="details" className="text-gray-300 data-[state=active]:text-white">
              Details
            </TabsTrigger>
            <TabsTrigger value="logs" className="text-gray-300 data-[state=active]:text-white">
              Logs
            </TabsTrigger>
          </TabsList>
          
          <TabsContent value="details" className="space-y-4 mt-4">
            {/* Status */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-400">Status</span>
              <Badge className={`${getStatusColor(orderDetails.status)} text-white capitalize`}>
                {orderDetails.status}
              </Badge>
            </div>

            {/* Trade Details */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-400">From</span>
                <div className="flex items-center space-x-2">
                  <img src={orderDetails.fromToken.logoURI} alt={orderDetails.fromToken.symbol} className="w-4 h-4" />
                  <span className="text-sm text-white">
                    {formatTokenAmount(orderDetails.fromAmount, orderDetails.fromToken.decimals)} {orderDetails.fromToken.symbol}
                  </span>
                </div>
              </div>
              
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-400">To</span>
                <div className="flex items-center space-x-2">
                  <img src={orderDetails.toToken.logoURI} alt={orderDetails.toToken.symbol} className="w-4 h-4" />
                  <span className="text-sm text-white">
                    {formatTokenAmount(orderDetails.toAmount, orderDetails.toToken.decimals)} {orderDetails.toToken.symbol}
                  </span>
                </div>
              </div>
            </div>

            {/* Strategy Details */}
            <div className="border-t border-gray-800 pt-4 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-400">Strategy</span>
                <span className="text-sm text-white">{orderDetails.strategyType}</span>
              </div>
              
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-400">Chunks</span>
                <span className="text-sm text-white">
                  {orderDetails.chunks.executed}/{orderDetails.chunks.total}
                </span>
              </div>
              
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-400">Volatility Threshold</span>
                <span className="text-sm text-white">{orderDetails.settings.volatilityThreshold}%</span>
              </div>
              
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-400">Chunk Interval</span>
                <span className="text-sm text-white">{orderDetails.settings.chunkInterval}s</span>
              </div>
            </div>

            {/* Timestamps */}
            <div className="border-t border-gray-800 pt-4">
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-400">Created</span>
                <span className="text-sm text-white">{formatDate(orderDetails.createdAt)}</span>
              </div>
            </div>
          </TabsContent>
          
          <TabsContent value="logs" className="space-y-4 mt-4">
            {/* Filter Buttons */}
            <div className="flex space-x-2">
              {['all', 'success', 'warning', 'error'].map((filter) => (
                <Button
                  key={filter}
                  variant={logFilter === filter ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => setLogFilter(filter)}
                  className={`capitalize ${
                    logFilter === filter 
                      ? 'bg-pink-600 text-white' 
                      : 'border-gray-700 text-gray-300 hover:bg-gray-800'
                  }`}
                >
                  {filter}
                </Button>
              ))}
            </div>

            {/* Logs List */}
            <div className="space-y-2 max-h-64 overflow-y-auto">
              {filteredLogs.map((log) => (
                <div key={log.id} className="bg-gray-800 rounded-lg p-3">
                  <div className="flex items-start space-x-3">
                    <span className="text-lg">{getLogIcon(log.type)}</span>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-white">{log.message}</p>
                      <div className="flex items-center space-x-2 mt-1">
                        <span className="text-xs text-gray-400">
                          {formatDate(log.timestamp)}
                        </span>
                        {log.txHash && (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="p-0 h-auto text-xs text-blue-400 hover:text-blue-300"
                          >
                            View tx
                          </Button>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}