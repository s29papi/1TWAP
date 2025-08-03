// app/providers.tsx
'use client'

import { WagmiConfig, createConfig, configureChains } from 'wagmi'
import { base } from 'wagmi/chains'
import { alchemyProvider } from 'wagmi/providers/alchemy'
import { publicProvider } from 'wagmi/providers/public'
import { MetaMaskConnector } from 'wagmi/connectors/metaMask'
import { WalletConnectConnector } from 'wagmi/connectors/walletConnect'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const { chains, publicClient, webSocketPublicClient } = configureChains(
  [base],
  [
    publicProvider()
  ]
)

const config = createConfig({
  autoConnect: true,
  connectors: [
    new MetaMaskConnector({ chains }),
    new WalletConnectConnector({
      chains,
      options: {
        projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_ID || 'YOUR_PROJECT_ID',
      },
    }),
  ],
  publicClient,
  webSocketPublicClient,
})

const queryClient = new QueryClient()

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiConfig config={config}>
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    </WagmiConfig>
  )
}