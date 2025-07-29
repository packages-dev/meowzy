'use client'

import { DocumentTextIcon } from '@heroicons/react/24/outline'

export function BillsList() {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900">Recent Bills</h3>
        <span className="text-sm text-gray-500">0 bills</span>
      </div>

      <div className="text-center py-8">
        <DocumentTextIcon className="mx-auto h-12 w-12 text-gray-400" />
        <h3 className="mt-4 text-sm font-medium text-gray-900">No bills yet</h3>
        <p className="mt-2 text-sm text-gray-500">
          Create a bill to start splitting expenses
        </p>
      </div>
    </div>
  )
}
