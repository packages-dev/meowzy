'use client'

import { ClockIcon } from '@heroicons/react/24/outline'

export function TransactionHistory() {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900">Transaction History</h3>
        <span className="text-sm text-gray-500">0 transactions</span>
      </div>

      <div className="text-center py-8">
        <ClockIcon className="mx-auto h-12 w-12 text-gray-400" />
        <h3 className="mt-4 text-sm font-medium text-gray-900">No transactions yet</h3>
        <p className="mt-2 text-sm text-gray-500">
          Your transaction history will appear here
        </p>
      </div>
    </div>
  )
}
