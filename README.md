# Cross Chain Bill Splitter

A comprehensive DeFi application for splitting bills across multiple blockchain networks using Merkle tree verification and cross-chain messaging.

## 🌟 Features

### Smart Contract Features
- **Cross-Chain Bill Splitting**: Split bills across Ethereum Sepolia, Polygon Mumbai, and Arbitrum Goerli
- **Merkle Tree Verification**: Gas-optimized verification of bill authenticity using Merkle proofs
- **Multi-Token Support**: Accept payments in various ERC20 tokens
- **Escrow & Dispute Resolution**: Secure payment handling with dispute mechanisms
- **Group Management**: Create and manage groups with member permissions
- **Three Split Types**: Equal, percentage-based, and custom amount splitting

### Frontend Features
- **Modern React/Next.js Interface**: Professional UI with Tailwind CSS
- **Multi-Wallet Support**: Connect with MetaMask, WalletConnect, and Coinbase Wallet
- **Real-time Updates**: Live transaction tracking and status updates
- **Cross-Chain Visualization**: Clear indication of multi-chain operations
- **Responsive Design**: Works seamlessly on desktop and mobile devices

## 🏗️ Architecture

### Smart Contracts
```
src/
├── CrossChainBillSplitter.sol    # Main coordinator contract
├── CrossChainBridge.sol          # Axelar Network integration
├── PaymentManager.sol            # Payment processing & escrow
└── MerkleVerifier.sol           # Merkle proof verification
```

### Frontend
```
frontend/src/
├── components/                   # React components
├── lib/                         # Utilities and Web3 config
├── types/                       # TypeScript definitions
└── app/                        # Next.js app router
```

## 🚀 Quick Start

### Prerequisites
- Node.js 18+ and npm
- Foundry (for smart contracts)
- Git

### Clone the Repository
```bash
git clone <repository-url>
cd cross-chain-bill-splitter
```

### Smart Contract Setup
```bash
cd contracts
forge install
forge build
forge test
```

### Frontend Setup
```bash
cd frontend
npm install
npm run dev
```

The frontend will be available at `http://localhost:3000`

## 🔧 Configuration

### Environment Variables
Create `.env.local` in the frontend directory:

```env
# Wallet Connect Project ID
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your-project-id

# RPC URLs
NEXT_PUBLIC_SEPOLIA_RPC_URL=https://rpc.sepolia.org
NEXT_PUBLIC_MUMBAI_RPC_URL=https://rpc.ankr.com/polygon_mumbai
NEXT_PUBLIC_ARBITRUM_GOERLI_RPC_URL=https://goerli-rollup.arbitrum.io/rpc

# Contract addresses (update after deployment)
NEXT_PUBLIC_SEPOLIA_BILL_SPLITTER=0x...
# ... (see .env.local template for all addresses)
```

### Contract Deployment
```bash
cd contracts
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

## 📱 How to Use

### 1. Connect Your Wallet
- Visit the application
- Click "Connect Wallet" and choose your preferred wallet
- Ensure you're connected to a supported testnet

### 2. Create a Group
- Click "Create Group" on the dashboard
- Add group members by their wallet addresses
- Set group permissions for bill creation

### 3. Create a Bill
- Select a group or create a new one
- Enter bill details (amount, description, due date)
- Choose split type (equal, percentage, or custom)
- For cross-chain bills, select participating networks

### 4. Pay Bills
- View your bills in the dashboard
- Click "Pay" on any outstanding bill
- Confirm the transaction in your wallet

### 5. Track Progress
- Monitor payment status in real-time
- View transaction history across all chains
- Resolve disputes if needed

## 🔗 Supported Networks

### Testnets
- **Ethereum Sepolia**: Primary network
- **Polygon Mumbai**: L2 scaling solution
- **Arbitrum Goerli**: Optimistic rollup

### Cross-Chain Protocol
- **Axelar Network**: Secure cross-chain messaging
- **Testnet Support**: Full testing on all supported chains

## 🛠️ Technical Details

### Smart Contract Architecture

#### CrossChainBillSplitter.sol
- Main entry point for all operations
- Group and bill management
- Member permission handling
- Integration with other contracts

#### CrossChainBridge.sol
- Axelar Network integration
- Cross-chain message handling
- Multi-chain payment coordination
- Chain settlement tracking

#### PaymentManager.sol
- ERC20 token payment processing
- Escrow functionality
- Dispute resolution mechanism
- Refund handling

#### MerkleVerifier.sol
- Gas-optimized Merkle proof verification
- Bill structure validation
- Batch verification support
- Equal/percentage split calculations

### Frontend Architecture

#### Web3 Integration
- Wagmi for React hooks
- Viem for low-level interactions
- Web3Modal for wallet connections
- TanStack Query for state management

#### UI Components
- Headless UI for accessible components
- Heroicons for consistent iconography
- Tailwind CSS for responsive styling
- TypeScript for type safety

## 🧪 Testing

### Smart Contract Tests
```bash
cd contracts
forge test -vv
```

### Test Coverage
- Unit tests for all core functions
- Integration tests for cross-contract interactions
- Edge case testing for error conditions
- Gas optimization verification

## 📊 Gas Optimization

The contracts are optimized for minimal gas usage:
- Merkle proofs for efficient verification
- Batch operations where possible
- Optimized storage layouts
- Minimal external calls

## 🔒 Security Features

- **Access Control**: Role-based permissions
- **Reentrancy Protection**: All external calls protected
- **Safe Math**: Overflow protection
- **Pausable Contracts**: Emergency stop functionality
- **Merkle Verification**: Cryptographic proof validation

## 🌍 Cross-Chain Flow

1. **Bill Creation**: Bill created on primary chain
2. **Cross-Chain Sync**: Bill synchronized across participating chains
3. **Multi-Chain Payments**: Users pay on their preferred chain
4. **Settlement**: Automatic settlement when all payments received
5. **Verification**: Merkle proofs ensure bill authenticity

## 📈 Future Enhancements

- [ ] Additional blockchain networks
- [ ] Mobile application
- [ ] Recurring bill support
- [ ] Advanced dispute resolution
- [ ] Analytics dashboard
- [ ] NFT receipt system
- [ ] Integration with payment providers

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Axelar Network** for cross-chain infrastructure
- **OpenZeppelin** for secure contract libraries
- **Foundry** for development framework
- **Next.js** and **React** for frontend framework
- **Tailwind CSS** for styling system

## 📞 Support

For questions and support:
- Create an issue in this repository
- Join our Discord community
- Follow our Twitter for updates

---

**Built with ❤️ for the DeFi community**
