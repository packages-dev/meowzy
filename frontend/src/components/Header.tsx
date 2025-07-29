'use client'

import { useAccount, useChainId, useDisconnect, useConnect } from 'wagmi'
import { formatAddress } from '@/lib/utils'
import { sepolia, polygonMumbai, arbitrumGoerli } from '@/lib/web3'
import { 
  WalletIcon,
  ChevronDownIcon,
  GlobeAltIcon,
  LinkIcon,
} from '@heroicons/react/24/outline'
import { Menu, Transition } from '@headlessui/react'
import { Fragment } from 'react'

const CHAIN_NAMES = {
  [sepolia.id]: 'Ethereum Sepolia',
  [polygonMumbai.id]: 'Polygon Mumbai', 
  [arbitrumGoerli.id]: 'Arbitrum Goerli',
}

function ConnectWallet() {
  const { connect, connectors } = useConnect()

  return (
    <Menu as="div" className="relative">
      <Menu.Button className="flex items-center space-x-2 bg-blue-600 text-white rounded-lg px-4 py-2 hover:bg-blue-700 transition-colors">
        <WalletIcon className="h-4 w-4" />
        <span className="text-sm font-medium">Connect Wallet</span>
        <ChevronDownIcon className="h-4 w-4" />
      </Menu.Button>

      <Transition
        as={Fragment}
        enter="transition ease-out duration-100"
        enterFrom="transform opacity-0 scale-95"
        enterTo="transform opacity-100 scale-100"
        leave="transition ease-in duration-75"
        leaveFrom="transform opacity-100 scale-100"
        leaveTo="transform opacity-0 scale-95"
      >
        <Menu.Items className="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
          {connectors.map((connector) => (
            <Menu.Item key={connector.id}>
              {({ active }) => (
                <button
                  onClick={() => connect({ connector })}
                  className={`${
                    active ? 'bg-gray-100' : ''
                  } block w-full px-4 py-2 text-left text-sm text-gray-700`}
                >
                  {connector.name}
                </button>
              )}
            </Menu.Item>
          ))}
        </Menu.Items>
      </Transition>
    </Menu>
  )
}

export function Header() {
  const { address, isConnected } = useAccount()
  const chainId = useChainId()
  const { disconnect } = useDisconnect()

  return (
    <header className="bg-white shadow-sm border-b border-gray-200">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 justify-between items-center">
          {/* Logo */}
          <div className="flex items-center">
            <LinkIcon className="h-8 w-8 text-blue-600" />
            <div className="ml-3">
              <h1 className="text-xl font-bold text-gray-900">
                Cross Chain Bill Splitter
              </h1>
              <p className="text-xs text-gray-500">
                Split bills across blockchains
              </p>
            </div>
          </div>

          {/* Navigation */}
          <nav className="hidden md:flex space-x-8">
            <a 
              href="#groups" 
              className="text-gray-500 hover:text-gray-900 px-3 py-2 text-sm font-medium"
            >
              Groups
            </a>
            <a 
              href="#bills" 
              className="text-gray-500 hover:text-gray-900 px-3 py-2 text-sm font-medium"
            >
              Bills
            </a>
            <a 
              href="#history" 
              className="text-gray-500 hover:text-gray-900 px-3 py-2 text-sm font-medium"
            >
              History
            </a>
          </nav>

          {/* Wallet Connection */}
          <div className="flex items-center space-x-4">
            {/* Chain Indicator */}
            {isConnected && (
              <div className="flex items-center space-x-2 bg-gray-100 rounded-lg px-3 py-2">
                <GlobeAltIcon className="h-4 w-4 text-gray-600" />
                <span className="text-sm text-gray-700">
                  {CHAIN_NAMES[chainId as keyof typeof CHAIN_NAMES] || 'Unknown Chain'}
                </span>
              </div>
            )}

            {/* Wallet */}
            {isConnected ? (
              <Menu as="div" className="relative">
                <Menu.Button className="flex items-center space-x-2 bg-blue-600 text-white rounded-lg px-4 py-2 hover:bg-blue-700 transition-colors">
                  <WalletIcon className="h-4 w-4" />
                  <span className="text-sm font-medium">
                    {formatAddress(address || '')}
                  </span>
                  <ChevronDownIcon className="h-4 w-4" />
                </Menu.Button>

                <Transition
                  as={Fragment}
                  enter="transition ease-out duration-100"
                  enterFrom="transform opacity-0 scale-95"
                  enterTo="transform opacity-100 scale-100"
                  leave="transition ease-in duration-75"
                  leaveFrom="transform opacity-100 scale-100"
                  leaveTo="transform opacity-0 scale-95"
                >
                  <Menu.Items className="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                    <Menu.Item>
                      {({ active }) => (
                        <button
                          onClick={() => disconnect()}
                          className={`${
                            active ? 'bg-gray-100' : ''
                          } block w-full px-4 py-2 text-left text-sm text-gray-700`}
                        >
                          Disconnect
                        </button>
                      )}
                    </Menu.Item>
                  </Menu.Items>
                </Transition>
              </Menu>
            ) : (
              <ConnectWallet />
            )}
          </div>
        </div>
      </div>
    </header>
  )
}
