'use client'

import { Header } from '@/components/Header'
import { Dashboard } from '@/components/Dashboard'

export default function Home() {
  return (
    <main className="min-h-screen bg-gray-50">
      <Header />
      <Dashboard />
    </main>
  )
}
