import { createWeb3Modal } from '@web3modal/wagmi'
import { http, createConfig } from 'wagmi'
import { sepolia, polygonMumbai, arbitrumGoerli } from 'wagmi/chains'
import { walletConnect, injected, coinbaseWallet } from 'wagmi/connectors'

// Get projectId from WalletConnect Cloud
const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'your-project-id'

// Create wagmi config
export const config = createConfig({
  chains: [sepolia, polygonMumbai, arbitrumGoerli],
  transports: {
    [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL || 'https://rpc.sepolia.org'),
    [polygonMumbai.id]: http(process.env.NEXT_PUBLIC_MUMBAI_RPC_URL || 'https://rpc.ankr.com/polygon_mumbai'),
    [arbitrumGoerli.id]: http(process.env.NEXT_PUBLIC_ARBITRUM_GOERLI_RPC_URL || 'https://goerli-rollup.arbitrum.io/rpc'),
  },
  connectors: [
    walletConnect({ projectId }),
    injected(),
    coinbaseWallet({ appName: 'Cross Chain Bill Splitter' }),
  ],
})

// Create modal
createWeb3Modal({
  wagmiConfig: config,
  projectId,
  themeMode: 'light',
  themeVariables: {
    '--w3m-accent': '#0EA5E9',
    '--w3m-border-radius-master': '8px',
  },
})

// Smart contract addresses (update after deployment)
export const CONTRACT_ADDRESSES = {
  [sepolia.id]: {
    CrossChainBillSplitter: '0x...',
    CrossChainBridge: '0x...',
    PaymentManager: '0x...',
    MerkleVerifier: '0x...',
  },
  [polygonMumbai.id]: {
    CrossChainBillSplitter: '0x...',
    CrossChainBridge: '0x...',
    PaymentManager: '0x...',
    MerkleVerifier: '0x...',
  },
  [arbitrumGoerli.id]: {
    CrossChainBillSplitter: '0x...',
    CrossChainBridge: '0x...',
    PaymentManager: '0x...',
    MerkleVerifier: '0x...',
  },
} as const

// ABI imports (will be generated from contracts)
export const ABIS = {
  CrossChainBillSplitter: [],
  CrossChainBridge: [],
  PaymentManager: [],
  MerkleVerifier: [],
}

export { sepolia, polygonMumbai, arbitrumGoerli }
