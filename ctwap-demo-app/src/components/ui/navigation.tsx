'use client'

import { useState } from 'react'
import { ChevronDownIcon, Cog6ToothIcon } from '@heroicons/react/24/outline'
import { Button } from '@/src/components/ui/button'

export default function Navigation() {
  const [isConnected, setIsConnected] = useState(false)
  const [address, setAddress] = useState('')

  const handleConnect = () => {
    // Mock wallet connection
    setIsConnected(true)
    setAddress('0x123...abc')
  }

  return (
    <nav className="border-b border-gray-800 bg-gray-900/50 backdrop-blur-sm">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          {/* Logo */}
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <h1 className="text-2xl font-bold text-pink-500">CTWAP</h1>
            </div>
            <div className="hidden md:block">
              <div className="ml-10 flex items-baseline space-x-4">
                <a href="#" className="text-white hover:text-pink-400 px-3 py-2 rounded-md text-sm font-medium">
                  Swap
                </a>
              </div>
            </div>
          </div>

          {/* Right side */}
          <div className="flex items-center space-x-4">
            {/* Network selector */}
            <div className="flex items-center space-x-2 bg-gray-800 rounded-lg px-3 py-2">
              <div className="w-2 h-2 bg-blue-500 rounded-full"></div>
              <span className="text-sm text-white">Base</span>
              <ChevronDownIcon className="h-4 w-4 text-gray-400" />
            </div>

            {/* Wallet connection */}
            {isConnected ? (
              <div className="flex items-center space-x-2 bg-gray-800 rounded-lg px-3 py-2">
                <div className="w-2 h-2 bg-green-500 rounded-full"></div>
                <span className="text-sm text-white">{address}</span>
              </div>
            ) : (
              <Button
                onClick={handleConnect}
                className="bg-pink-600 hover:bg-pink-700 text-white"
              >
                Connect Wallet
              </Button>
            )}

            {/* Settings */}
            <button className="p-2 text-gray-400 hover:text-white">
              <Cog6ToothIcon className="h-5 w-5" />
            </button>
          </div>
        </div>
      </div>
    </nav>
  )
}