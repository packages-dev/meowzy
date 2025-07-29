'use client'

import { useAccount } from 'wagmi'
import { CreateGroupModal } from './CreateGroupModal'
import { CreateBillModal } from './CreateBillModal'
import { GroupsList } from './GroupsList'
import { BillsList } from './BillsList'
import { TransactionHistory } from './TransactionHistory'
import { PlusIcon, UserGroupIcon, DocumentTextIcon } from '@heroicons/react/24/outline'
import { useState } from 'react'

export function Dashboard() {
  const { isConnected } = useAccount()
  const [showCreateGroup, setShowCreateGroup] = useState(false)
  const [showCreateBill, setShowCreateBill] = useState(false)

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[calc(100vh-4rem)] px-4">
        <div className="text-center">
          <UserGroupIcon className="mx-auto h-16 w-16 text-gray-400" />
          <h2 className="mt-6 text-3xl font-bold text-gray-900">
            Connect Your Wallet
          </h2>
          <p className="mt-4 text-lg text-gray-600 max-w-md">
            Connect your wallet to start creating groups and splitting bills across different blockchain networks.
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8">
      {/* Quick Actions */}
      <div className="mb-8">
        <h2 className="text-2xl font-bold text-gray-900 mb-4">Quick Actions</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <button
            onClick={() => setShowCreateGroup(true)}
            className="flex items-center justify-center space-x-3 bg-white p-6 border-2 border-dashed border-gray-300 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-colors group"
          >
            <PlusIcon className="h-8 w-8 text-gray-400 group-hover:text-blue-500" />
            <div className="text-left">
              <h3 className="text-lg font-semibold text-gray-900 group-hover:text-blue-600">
                Create Group
              </h3>
              <p className="text-sm text-gray-500">
                Start a new group for bill splitting
              </p>
            </div>
          </button>

          <button
            onClick={() => setShowCreateBill(true)}
            className="flex items-center justify-center space-x-3 bg-white p-6 border-2 border-dashed border-gray-300 rounded-lg hover:border-green-500 hover:bg-green-50 transition-colors group"
          >
            <DocumentTextIcon className="h-8 w-8 text-gray-400 group-hover:text-green-500" />
            <div className="text-left">
              <h3 className="text-lg font-semibold text-gray-900 group-hover:text-green-600">
                Create Bill
              </h3>
              <p className="text-sm text-gray-500">
                Add a new bill to split with others
              </p>
            </div>
          </button>
        </div>
      </div>

      {/* Main Content Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Groups */}
        <div className="lg:col-span-1">
          <GroupsList />
        </div>

        {/* Bills */}
        <div className="lg:col-span-2">
          <BillsList />
        </div>
      </div>

      {/* Transaction History */}
      <div className="mt-8">
        <TransactionHistory />
      </div>

      {/* Modals */}
      <CreateGroupModal 
        open={showCreateGroup} 
        onClose={() => setShowCreateGroup(false)} 
      />
      <CreateBillModal 
        open={showCreateBill} 
        onClose={() => setShowCreateBill(false)} 
      />
    </div>
  )
}
