// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title OneInchIntegrationExample
 * @dev Example showing how to integrate 1inch with your CrossChainBridge
 * @notice This demonstrates the workflow for swapping tokens and sending cross-chain
 */

/* 
INTEGRATION GUIDE: How to use 1inch with CrossChainBridge

1. OFF-CHAIN PREPARATION:
   - Call 1inch API to get swap data and quote
   - Example API call: https://api.1inch.dev/swap/v5.2/1/swap
   - Parameters needed:
     * src: source token address
     * dst: destination token address  
     * amount: amount to swap
     * from: your contract address
     * slippage: acceptable slippage (e.g., 1 for 1%)

2. FRONTEND INTEGRATION:
   ```javascript
   // Get 1inch swap data
   const oneInchUrl = `https://api.1inch.dev/swap/v5.2/${chainId}/swap`;
   const params = {
     src: fromTokenAddress,
     dst: toTokenAddress,
     amount: amount,
     from: contractAddress,
     slippage: 1, // 1%
     disableEstimate: true
   };
   
   const response = await fetch(`${oneInchUrl}?${new URLSearchParams(params)}`);
   const swapData = await response.json();
   
   // Call your contract
   await contract.payBillWithSwap(
     billId,
     fromTokenAddress,
     amount,
     "USDC",
     "polygon",
     destinationAddress,
     swapData.tx.data, // This is the swap data
     swapData.toAmount // Minimum amount expected
   );
   ```

3. CONTRACT USAGE FLOW:
   
   Step 1: User approves your contract to spend their tokens
   Step 2: User calls payBillWithSwap() with 1inch data
   Step 3: Contract swaps tokens via 1inch
   Step 4: Contract sends swapped tokens cross-chain via Axelar
   
4. EXAMPLE TRANSACTION FLOW:
   
   User wants to pay a 100 USDC bill on Polygon, but only has WETH on Ethereum
   
   1. Get quote from 1inch: "0.1 WETH → 100 USDC on Ethereum"
   2. Get 1inch swap data for: WETH → axlUSDC (Axelar's USDC)
   3. Call payBillWithSwap():
      - paymentToken: WETH address
      - paymentAmount: 0.1 ether
      - targetTokenSymbol: "axlUSDC"
      - destinationChain: "polygon"
      - oneInchSwapData: from API
      - minTargetAmount: 95 * 1e6 (95 USDC with slippage)
   
   4. Contract executes:
      - Swaps 0.1 WETH → 100 axlUSDC via 1inch
      - Sends 100 axlUSDC to Polygon via Axelar
      - Bill gets paid on Polygon

5. BENEFITS:
   - Users can pay with ANY token they hold
   - Automatic best price discovery via 1inch
   - Cross-chain compatibility via Axelar
   - Reduced friction for bill payments

6. DEPLOYMENT CONSIDERATIONS:
   
   - Update 1inch router addresses for each network
   - Set proper slippage tolerances
   - Handle failed swaps gracefully  
   - Monitor gas costs for complex swaps
   - Consider implementing price impact limits

7. TESTING:
   
   For testing on localhost/anvil:
   - Deploy mock ERC20 tokens
   - Create a mock 1inch router that does simple swaps
   - Test the full flow: approve → swap → send cross-chain

8. SECURITY CONSIDERATIONS:
   
   - Always validate 1inch swap data
   - Set reasonable slippage limits
   - Use reentrancy guards
   - Implement emergency pause functionality
   - Regular security audits for 1inch integration

9. GAS OPTIMIZATION:
   
   - Batch approvals where possible
   - Use permit() tokens to save gas
   - Consider gas-efficient swap routes
   - Optimize cross-chain message payloads

10. ERROR HANDLING:
    
    - Handle 1inch swap failures
    - Implement refund mechanisms
    - Add proper error messages
    - Log failed transactions for debugging
*/

contract OneInchUsageExample {
    // This contract demonstrates the key concepts
    // Actual implementation should use CrossChainBridgeWithSwap
    
    event ExampleSwapAndSend(
        address indexed user,
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256 amountOut,
        string destinationChain
    );
    
    // Example function signature for reference
    function examplePayBillWithSwap(
        bytes32 billId,
        address paymentToken,      // Token user wants to pay with (e.g., WETH)
        uint256 paymentAmount,     // Amount of payment token (e.g., 0.1 WETH)
        string calldata targetTokenSymbol, // Required token symbol (e.g., "USDC")
        string calldata destinationChain,  // Target chain (e.g., "polygon")
        address destinationAddress,        // Target address
        bytes calldata oneInchSwapData,    // From 1inch API
        uint256 minTargetAmount            // Minimum expected (with slippage)
    ) external payable {
        // This would be implemented in CrossChainBridgeWithSwap
        emit ExampleSwapAndSend(
            msg.sender,
            paymentToken,
            address(0), // toToken would be resolved from symbol
            paymentAmount,
            minTargetAmount,
            destinationChain
        );
    }
}
