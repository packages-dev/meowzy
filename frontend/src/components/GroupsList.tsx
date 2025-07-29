'use client'

import { UserGroupIcon } from '@heroicons/react/24/outline'

export function GroupsList() {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900">My Groups</h3>
        <span className="text-sm text-gray-500">0 groups</span>
      </div>

      <div className="text-center py-8">
        <UserGroupIcon className="mx-auto h-12 w-12 text-gray-400" />
        <h3 className="mt-4 text-sm font-medium text-gray-900">No groups yet</h3>
        <p className="mt-2 text-sm text-gray-500">
          Create your first group to start splitting bills
        </p>
      </div>
    </div>
  )
}
