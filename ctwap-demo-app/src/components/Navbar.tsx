// components/Navbar.tsx
'use client'

import { useAccount, useConnect, useDisconnect, useNetwork, useSwitchNetwork } from 'wagmi'
import { useState } from 'react'
import { ChevronDown, Wallet, Settings, MoreHorizontal } from 'lucide-react'

export function Navbar() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()
  const { chain } = useNetwork()
  const { switchNetwork } = useSwitchNetwork()
  const [showWalletModal, setShowWalletModal] = useState(false)

  const formatAddress = (addr: string) => {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`
  }

  return (
    <nav className="border-b border-gray-800 bg-[#0d0d0d]">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <div className="flex items-center space-x-8">
            <div className="flex items-center space-x-2">
              <div className="w-8 h-8 bg-gradient-to-br from-pink-500 to-pink-600 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold text-sm">C</span>
              </div>
              <span className="text-white font-semibold text-lg">CTWAP</span>
            </div>
            
            {/* Nav Links */}
            <div className="hidden md:flex items-center space-x-6">
              <button className="text-white hover:text-gray-300 transition-colors">
                Swap
              </button>
              <button className="text-gray-400 hover:text-gray-300 transition-colors">
                Pool
              </button>
              <button className="text-gray-400 hover:text-gray-300 transition-colors">
                Analytics
              </button>
            </div>
          </div>

          {/* Right Section */}
          <div className="flex items-center space-x-3">
            {/* Network Selector */}
            {isConnected && chain?.id !== 8453 && (
              <button
                onClick={() => switchNetwork?.(8453)}
                className="px-4 py-2 bg-red-500/10 border border-red-500/20 rounded-xl text-red-400 hover:bg-red-500/20 transition-colors"
              >
                Switch to Base
              </button>
            )}

            {/* Connect Button */}
            {!isConnected ? (
              <button
                onClick={() => setShowWalletModal(true)}
                className="px-4 py-2 bg-pink-500 hover:bg-pink-600 text-white rounded-xl font-medium transition-colors flex items-center space-x-2"
              >
                <Wallet className="w-4 h-4" />
                <span>Connect Wallet</span>
              </button>
            ) : (
              <button
                onClick={() => disconnect()}
                className="px-4 py-2 bg-[#1a1a1a] hover:bg-[#222] border border-gray-800 rounded-xl text-white font-medium transition-colors flex items-center space-x-2"
              >
                <div className="w-2 h-2 bg-green-400 rounded-full" />
                <span>{formatAddress(address!)}</span>
                <ChevronDown className="w-4 h-4" />
              </button>
            )}

            {/* Settings */}
            <button className="p-2 text-gray-400 hover:text-white transition-colors">
              <Settings className="w-5 h-5" />
            </button>

            {/* More */}
            <button className="p-2 text-gray-400 hover:text-white transition-colors">
              <MoreHorizontal className="w-5 h-5" />
            </button>
          </div>
        </div>
      </div>

      {/* Wallet Modal */}
      {showWalletModal && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-[#131313] border border-gray-800 rounded-2xl p-6 w-full max-w-md">
            <h2 className="text-xl font-semibold text-white mb-4">Connect a wallet</h2>
            
            <div className="space-y-3">
              {connectors.map((connector) => (
                <button
                  key={connector.id}
                  onClick={() => {
                    connect({ connector })
                    setShowWalletModal(false)
                  }}
                  className="w-full p-4 bg-[#1a1a1a] hover:bg-[#222] border border-gray-800 rounded-xl text-white font-medium transition-colors text-left"
                >
                  {connector.name}
                </button>
              ))}
            </div>

            <button
              onClick={() => setShowWalletModal(false)}
              className="mt-4 w-full p-3 text-gray-400 hover:text-white transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </nav>
  )
}