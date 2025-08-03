// app/page.tsx
'use client'

import { useState } from 'react'
import { Navbar } from '@/components/Navbar'
import { SwapInterface } from '@/components/SwapInterface'
import { OrderDetails } from '@/components/OrderDetails'
import { ExecutionMonitor } from '@/components/ExecutionMonitor'
import { ChartContainer } from '@/components/ChartContainer'

export default function Home() {
  const [activeOrderHash, setActiveOrderHash] = useState<string>('')
  const [isMonitoring, setIsMonitoring] = useState(false)

  return (
    <div className="min-h-screen bg-[#131313]">
      <Navbar />
      
      <main className="container mx-auto px-4 py-8 max-w-7xl">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Column - Swap Interface */}
          <div className="lg:col-span-1">
            <SwapInterface 
              onOrderCreated={(orderHash) => {
                setActiveOrderHash(orderHash)
                setIsMonitoring(true)
              }}
            />
          </div>
          
          {/* Middle Column - Charts and Monitor */}
          <div className="lg:col-span-1 space-y-6">
            <ChartContainer orderHash={activeOrderHash} />
            <ExecutionMonitor 
              orderHash={activeOrderHash}
              isMonitoring={isMonitoring}
              onToggleMonitoring={() => setIsMonitoring(!isMonitoring)}
            />
          </div>
          
          {/* Right Column - Order Details and Logs */}
          <div className="lg:col-span-1">
            <OrderDetails 
              orderHash={activeOrderHash}
              isActive={isMonitoring}
            />
          </div>
        </div>
      </main>
    </div>
  )
}