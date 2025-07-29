import { Address } from 'viem'

export interface Group {
  groupId: string
  name: string
  description: string
  creator: Address
  members: Address[]
  createdAt: number
  totalBills: number
  totalSettled: number
  active: boolean
}

export interface Bill {
  billId: string
  groupId: string
  creator: Address
  description: string
  totalAmount: bigint
  paymentToken: Address
  splitType: SplitType
  members: Address[]
  memberAmounts: bigint[]
  createdAt: number
  dueDate: number
  crossChain: boolean
  participatingChains: string[]
  chainAmounts: Record<string, bigint>
  settled: boolean
  disputed: boolean
}

export interface CrossChainBill {
  billId: string
  creator: Address
  totalAmount: bigint
  symbol: string
  participatingChains: string[]
  chainAmounts: Record<string, bigint>
  chainSettled: Record<string, boolean>
  fullySettled: boolean
  createdAt: number
}

export interface PendingPayment {
  billId: string
  payer: Address
  amount: bigint
  symbol: string
  sourceChain: string
  timestamp: number
  processed: boolean
}

export enum SplitType {
  EQUAL = 0,
  PERCENTAGE = 1,
  CUSTOM = 2,
}

export interface BillStructure {
  totalAmount: bigint
  splitType: SplitType
  members: Address[]
  amounts: bigint[]
  timestamp: number
  billId: string
}

export interface PaymentInfo {
  billId: string
  totalAmount: bigint
  paidAmount: bigint
  paymentToken: Address
  creator: Address
  settled: boolean
  disputed: boolean
  disputeReason: string
  memberPaid: Record<Address, boolean>
  memberAmounts: Record<Address, bigint>
}

export interface CreateGroupForm {
  name: string
  description: string
  members: string[]
}

export interface CreateBillForm {
  groupId: string
  description: string
  totalAmount: string
  paymentToken: string
  splitType: SplitType
  memberAmounts?: string[]
  dueDate: Date
  crossChain: boolean
  participatingChains?: string[]
  chainAmounts?: string[]
}

export interface NetworkConfig {
  chainId: number
  name: string
  symbol: string
  rpcUrl: string
  blockExplorer: string
  contracts: {
    CrossChainBillSplitter: Address
    CrossChainBridge: Address
    PaymentManager: Address
    MerkleVerifier: Address
  }
}

export interface TransactionStatus {
  hash: string
  status: 'pending' | 'confirmed' | 'failed'
  chainId: number
  timestamp: number
  gasUsed?: bigint
  error?: string
}

export interface WalletState {
  address?: Address
  chainId?: number
  isConnected: boolean
  isConnecting: boolean
  error?: string
}
