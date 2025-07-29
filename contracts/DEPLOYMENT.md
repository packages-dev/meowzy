# Smart Contract Deployment Guide

This guide walks you through deploying the Cross Chain Bill Splitter smart contracts to testnets.

## Prerequisites

1. **Foundry installed**: Install from [getfoundry.sh](https://getfoundry.sh)
2. **Testnet ETH**: Get from faucets for each network
3. **RPC URLs**: Alchemy, Infura, or public RPC endpoints
4. **Private key**: For deployment (use a testnet-only wallet)

## Environment Setup

Create a `.env` file in the `contracts` directory:

```bash
# Private key for deployment (without 0x prefix)
PRIVATE_KEY=your_private_key_here

# RPC URLs
SEPOLIA_RPC_URL=https://rpc.sepolia.org
MUMBAI_RPC_URL=https://rpc.ankr.com/polygon_mumbai
ARBITRUM_GOERLI_RPC_URL=https://goerli-rollup.arbitrum.io/rpc

# Etherscan API keys for verification
ETHERSCAN_API_KEY=your_etherscan_api_key
POLYGONSCAN_API_KEY=your_polygonscan_api_key
ARBISCAN_API_KEY=your_arbiscan_api_key

# Axelar addresses (already configured for testnets)
AXELAR_GATEWAY_SEPOLIA=0xe432150cce91c13a887f7D836923d5597adD8E31
AXELAR_GATEWAY_MUMBAI=0xBF62ef1486468a6bd26Dd669C06db43dEd5B849B
AXELAR_GATEWAY_ARBITRUM=0xe432150cce91c13a887f7D836923d5597adD8E31

AXELAR_GAS_SERVICE_SEPOLIA=0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6
AXELAR_GAS_SERVICE_MUMBAI=0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6
AXELAR_GAS_SERVICE_ARBITRUM=0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6
```

## Pre-Deployment Checklist

1. **Compile contracts**:
   ```bash
   cd contracts
   forge build
   ```

2. **Run tests**:
   ```bash
   forge test
   ```

3. **Check gas estimates**:
   ```bash
   forge test --gas-report
   ```

## Deployment Process

### Step 1: Deploy to Sepolia (Primary Network)

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

**Expected output:**
```
== Logs ==
Deploying to chain: 11155111
Deployer: 0x...
MerkleVerifier deployed at: 0x...
PaymentManager deployed at: 0x...
CrossChainBridge deployed at: 0x...
CrossChainBillSplitter deployed at: 0x...
```

### Step 2: Deploy to Polygon Mumbai

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $MUMBAI_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $POLYGONSCAN_API_KEY
```

### Step 3: Deploy to Arbitrum Goerli

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $ARBITRUM_GOERLI_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY
```

## Post-Deployment Configuration

### 1. Update Frontend Configuration

Copy the deployed contract addresses to `frontend/.env.local`:

```bash
# Sepolia addresses
NEXT_PUBLIC_SEPOLIA_BILL_SPLITTER=0x...
NEXT_PUBLIC_SEPOLIA_BRIDGE=0x...
NEXT_PUBLIC_SEPOLIA_PAYMENT_MANAGER=0x...
NEXT_PUBLIC_SEPOLIA_MERKLE_VERIFIER=0x...

# Mumbai addresses
NEXT_PUBLIC_MUMBAI_BILL_SPLITTER=0x...
NEXT_PUBLIC_MUMBAI_BRIDGE=0x...
NEXT_PUBLIC_MUMBAI_PAYMENT_MANAGER=0x...
NEXT_PUBLIC_MUMBAI_MERKLE_VERIFIER=0x...

# Arbitrum addresses
NEXT_PUBLIC_ARBITRUM_BILL_SPLITTER=0x...
NEXT_PUBLIC_ARBITRUM_BRIDGE=0x...
NEXT_PUBLIC_ARBITRUM_PAYMENT_MANAGER=0x...
NEXT_PUBLIC_ARBITRUM_MERKLE_VERIFIER=0x...
```

### 2. Configure Cross-Chain Trust

The bridges need to trust each other across chains:

```bash
# On each chain, set trusted remotes
cast send $BRIDGE_ADDRESS \
  "setTrustedRemote(string,address)" \
  "ethereum-sepolia" \
  $SEPOLIA_BRIDGE_ADDRESS

cast send $BRIDGE_ADDRESS \
  "setTrustedRemote(string,address)" \
  "polygon-mumbai" \
  $MUMBAI_BRIDGE_ADDRESS

cast send $BRIDGE_ADDRESS \
  "setTrustedRemote(string,address)" \
  "arbitrum-goerli" \
  $ARBITRUM_BRIDGE_ADDRESS
```

### 3. Add Supported Chains

Enable cross-chain operations:

```bash
# Add chain support
cast send $BRIDGE_ADDRESS \
  "addSupportedChain(string)" \
  "polygon-mumbai"

cast send $BRIDGE_ADDRESS \
  "addSupportedChain(string)" \
  "arbitrum-goerli"
```

## Verification

### 1. Check Deployments

Visit the block explorers:
- **Sepolia**: https://sepolia.etherscan.io
- **Mumbai**: https://mumbai.polygonscan.com
- **Arbitrum**: https://goerli.arbiscan.io

### 2. Test Basic Functions

```bash
# Test group creation
cast send $BILL_SPLITTER_ADDRESS \
  "createGroup(string,string,address[])" \
  "Test Group" \
  "Testing deployment" \
  "[0x...]"

# Verify group was created
cast call $BILL_SPLITTER_ADDRESS \
  "groupCount()" \
  | xargs printf "%d\n"
```

### 3. Test Cross-Chain Setup

```bash
# Check supported chains
cast call $BRIDGE_ADDRESS \
  "supportedChains(string)" \
  "polygon-mumbai"

# Should return: true
```

## Troubleshooting

### Common Issues

1. **Insufficient gas price**:
   ```bash
   # Add --gas-price flag
   --gas-price 20000000000  # 20 gwei
   ```

2. **Verification failed**:
   ```bash
   # Verify manually
   forge verify-contract \
     --chain sepolia \
     --etherscan-api-key $ETHERSCAN_API_KEY \
     $CONTRACT_ADDRESS \
     src/ContractName.sol:ContractName
   ```

3. **RPC rate limiting**:
   - Use paid RPC providers (Alchemy, Infura)
   - Add delays between deployments

### Contract Addresses Backup

Keep a record of all deployed addresses:

```json
{
  "sepolia": {
    "chainId": 11155111,
    "contracts": {
      "MerkleVerifier": "0x...",
      "PaymentManager": "0x...",
      "CrossChainBridge": "0x...",
      "CrossChainBillSplitter": "0x..."
    }
  },
  "mumbai": {
    "chainId": 80001,
    "contracts": {
      "MerkleVerifier": "0x...",
      "PaymentManager": "0x...",
      "CrossChainBridge": "0x...",
      "CrossChainBillSplitter": "0x..."
    }
  },
  "arbitrumGoerli": {
    "chainId": 421613,
    "contracts": {
      "MerkleVerifier": "0x...",
      "PaymentManager": "0x...",
      "CrossChainBridge": "0x...",
      "CrossChainBillSplitter": "0x..."
    }
  }
}
```

## Security Considerations

1. **Private Key Security**: Never commit private keys to version control
2. **Testnet Only**: These configurations are for testnets only
3. **Access Control**: Set up proper admin roles after deployment
4. **Pause Functionality**: Test emergency pause features

## Next Steps

After successful deployment:

1. Update the frontend with contract addresses
2. Generate and include contract ABIs
3. Test the full application flow
4. Set up monitoring and alerting
5. Prepare for potential mainnet deployment

---

**Note**: Always test thoroughly on testnets before considering mainnet deployment.
