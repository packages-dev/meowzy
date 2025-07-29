import { type ClassValue, clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatAddress(address: string): string {
  if (!address) return ''
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

export function formatCurrency(
  amount: bigint | number,
  decimals: number = 18,
  symbol: string = 'ETH'
): string {
  const formatted = typeof amount === 'bigint' 
    ? Number(amount) / Math.pow(10, decimals)
    : amount
  
  return `${formatted.toFixed(4)} ${symbol}`
}

export function formatDate(date: Date | number): string {
  const d = typeof date === 'number' ? new Date(date * 1000) : date
  return d.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export async function generateBillId(groupId: string, creator: string, timestamp: number): Promise<string> {
  // This mimics the contract's bill ID generation
  const encoder = new TextEncoder()
  const data = encoder.encode(`${groupId}${creator}${timestamp}`)
  const hash = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(hash))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')
}

export function validateAmount(amount: string): boolean {
  const num = parseFloat(amount)
  return !isNaN(num) && num > 0
}

export function validateAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address)
}

export function parseAmount(amount: string, decimals: number = 18): bigint {
  const num = parseFloat(amount)
  return BigInt(Math.floor(num * Math.pow(10, decimals)))
}

export function truncateText(text: string, maxLength: number): string {
  if (text.length <= maxLength) return text
  return text.slice(0, maxLength) + '...'
}
