// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title OneInchIntegration
 * @dev Integration with 1inch aggregation router for token swaps
 */
contract OneInchIntegration {
    using SafeERC20 for IERC20;
    
    // 1inch router addresses for different networks
    mapping(uint256 => address) public oneInchRouters;
    
    // Events
    event TokenSwapped(
        address indexed fromToken,
        address indexed toToken,
        uint256 amountIn,
        uint256 amountOut,
        address indexed user
    );
    
    // Errors
    error SwapFailed();
    error InvalidRouter();
    error InvalidSwapData();
    
    constructor() {
        // Initialize 1inch router addresses for different chains
        _initializeRouters();
    }
    
    /**
     * @dev Initialize 1inch router addresses for supported chains
     */
    function _initializeRouters() internal {
        // Ethereum Mainnet
        oneInchRouters[1] = 0x111111125421cA6dc452d289314280a0f8842A65;
        // Polygon
        oneInchRouters[137] = 0x111111125421cA6dc452d289314280a0f8842A65;
        // Arbitrum
        oneInchRouters[42161] = 0x111111125421cA6dc452d289314280a0f8842A65;
        // BSC
        oneInchRouters[56] = 0x111111125421cA6dc452d289314280a0f8842A65;
        // Optimism
        oneInchRouters[10] = 0x111111125421cA6dc452d289314280a0f8842A65;
        
        // Testnets (use mainnet addresses for now, update with actual testnet addresses)
        oneInchRouters[11155111] = 0x111111125421cA6dc452d289314280a0f8842A65; // Sepolia
        oneInchRouters[80001] = 0x111111125421cA6dc452d289314280a0f8842A65;    // Mumbai
        oneInchRouters[421613] = 0x111111125421cA6dc452d289314280a0f8842A65;   // Arbitrum Goerli
    }
    
    /**
     * @dev Swap tokens using 1inch aggregation
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @param amount Amount to swap
     * @param swapData Encoded swap data from 1inch API
     * @param minAmountOut Minimum amount expected from swap
     * @return amountOut Actual amount received from swap
     */
    function swapTokens(
        address fromToken,
        address toToken,
        uint256 amount,
        bytes calldata swapData,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        address router = oneInchRouters[block.chainid];
        if (router == address(0)) revert InvalidRouter();
        
        uint256 balanceBefore = IERC20(toToken).balanceOf(address(this));
        
        // Transfer from token to this contract if not already done
        IERC20(fromToken).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve router to spend fromToken
        IERC20(fromToken).forceApprove(router, amount);
        
        // Execute swap through 1inch router
        (bool success,) = router.call(swapData);
        if (!success) revert SwapFailed();
        
        uint256 balanceAfter = IERC20(toToken).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        
        if (amountOut < minAmountOut) revert SwapFailed();
        
        emit TokenSwapped(fromToken, toToken, amount, amountOut, msg.sender);
        
        return amountOut;
    }
    
    /**
     * @dev Get quote for token swap from 1inch
     * @dev This should be called off-chain to get swap data
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @param amount Amount to swap
     * @return estimatedAmountOut Estimated output amount
     */
    function getSwapQuote(
        address fromToken,
        address toToken,
        uint256 amount
    ) external view returns (uint256 estimatedAmountOut) {
        // This is a placeholder - in practice, you'd call 1inch API off-chain
        // to get the quote and swap data, then pass it to the swapTokens function
        // For now, return a simple estimation
        return amount; // Simplified 1:1 for example
    }
    
    /**
     * @dev Update 1inch router address for a specific chain
     * @param chainId Chain ID
     * @param router New router address
     */
    function updateOneInchRouter(uint256 chainId, address router) external {
        // Add access control in your implementation
        oneInchRouters[chainId] = router;
    }
}
