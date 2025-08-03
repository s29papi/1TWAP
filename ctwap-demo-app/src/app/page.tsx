'use client'

import { Toaster } from 'react-hot-toast'
import Navigation from '@/src/components/ui/navigation'
import SwapInterface from '@/src/components/swap/swap-interface'
import VolatilityChart from '@/src/components/charts/volatility-chart'
import ExecutionMonitor from '@/src/components/monitoring/execution-monitor'
import OrderDetails from '@/src/components/orders/order-details'

export default function Home() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-gray-800 to-black">
      <Navigation />
      
      <main className="container mx-auto px-4 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left Column - Swap Interface */}
          <div className="lg:col-span-4">
            <SwapInterface />
          </div>
          
          {/* Middle Column - Charts and Monitoring */}
          <div className="lg:col-span-4 space-y-6">
            <VolatilityChart />
            <ExecutionMonitor />
          </div>
          
          {/* Right Column - Order Details */}
          <div className="lg:col-span-4">
            <OrderDetails />
          </div>
        </div>
        
        {/* Mobile/Tablet responsive adjustments */}
        <div className="lg:hidden">
          <div className="text-center text-gray-400 mt-8 p-4">
            <p className="text-sm">
              For the best experience, use a desktop browser. Mobile layout optimizations in progress.
            </p>
          </div>
        </div>
      </main>
      
      <Toaster
        position="bottom-right"
        toastOptions={{
          style: {
            background: '#1F2937',
            color: '#fff',
            border: '1px solid #374151',
          },
        }}
      />
    </div>
  )
}