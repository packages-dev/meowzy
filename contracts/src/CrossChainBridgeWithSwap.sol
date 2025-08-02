// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./CrossChainBridge.sol";
import "./IOneInchAggregator.sol";

/**
 * @title CrossChainBridgeWithSwap
 * @dev Extension of CrossChainBridge with 1inch swap integration
 * @notice Allows users to pay bills with any token by automatically swapping to required token
 */
contract CrossChainBridgeWithSwap is CrossChainBridge {
    using SafeERC20 for IERC20;
    
    // 1inch Aggregation Router addresses for different chains
    mapping(uint256 => address) public oneInchRouters;
    
    // Events
    event TokenSwappedForBill(
        bytes32 indexed billId,
        address indexed fromToken,
        address indexed toToken,
        uint256 amountIn,
        uint256 amountOut,
        address user
    );
    
    event SwapAndCrossChainSent(
        bytes32 indexed billId,
        address fromToken,
        string toTokenSymbol,
        uint256 amountIn,
        uint256 amountOut,
        string destinationChain
    );
    
    // Errors
    error SwapFailed();
    error OneInchRouterNotSet();
    error InsufficientSwapOutput();
    
    constructor(
        address _gateway,
        address _gasService
    ) CrossChainBridge(_gateway, _gasService) {
        _initializeOneInchRouters();
    }
    
    /**
     * @dev Initialize 1inch router addresses for different chains
     */
    function _initializeOneInchRouters() internal {
        // Mainnet addresses
        oneInchRouters[1] = 0x111111125421cA6dc452d289314280a0f8842A65;      // Ethereum
        oneInchRouters[137] = 0x111111125421cA6dc452d289314280a0f8842A65;    // Polygon
        oneInchRouters[42161] = 0x111111125421cA6dc452d289314280a0f8842A65;  // Arbitrum
        oneInchRouters[10] = 0x111111125421cA6dc452d289314280a0f8842A65;     // Optimism
        oneInchRouters[56] = 0x111111125421cA6dc452d289314280a0f8842A65;     // BSC
        
        // Testnet addresses (you should verify these)
        oneInchRouters[11155111] = 0x111111125421cA6dc452d289314280a0f8842A65; // Sepolia
        oneInchRouters[80001] = 0x111111125421cA6dc452d289314280a0f8842A65;    // Mumbai
        oneInchRouters[421613] = 0x111111125421cA6dc452d289314280a0f8842A65;   // Arbitrum Goerli
        
        // Localhost/Anvil (for testing)
        oneInchRouters[31337] = 0x111111125421cA6dc452d289314280a0f8842A65;
    }
    
    /**
     * @dev Pay for a cross-chain bill with any ERC20 token
     * @param billId The bill identifier
     * @param paymentToken Token the user wants to pay with
     * @param paymentAmount Amount of payment token
     * @param targetTokenSymbol Symbol of the required token for the bill
     * @param destinationChain Target chain name
     * @param destinationAddress Target address on destination chain
     * @param oneInchSwapData Encoded swap data from 1inch API
     * @param minTargetAmount Minimum amount of target token expected
     */
    function payBillWithSwap(
        bytes32 billId,
        address paymentToken,
        uint256 paymentAmount,
        string calldata targetTokenSymbol,
        string calldata destinationChain,
        address destinationAddress,
        bytes calldata oneInchSwapData,
        uint256 minTargetAmount
    ) external payable nonReentrant whenNotPaused {
        if (billId == bytes32(0)) revert InvalidBillId();
        if (!supportedChains[destinationChain]) revert InvalidChain();
        if (paymentAmount == 0) revert InvalidAmount();
        
        // Get target token address
        address targetToken = gatewayWithToken().tokenAddresses(targetTokenSymbol);
        if (targetToken == address(0)) revert InvalidAmount();
        
        uint256 targetAmount;
        
        // If payment token is the same as target token, no swap needed
        if (paymentToken == targetToken) {
            IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);
            targetAmount = paymentAmount;
        } else {
            // Perform 1inch swap
            targetAmount = _swapTokensViaOneInch(
                paymentToken,
                targetToken,
                paymentAmount,
                oneInchSwapData,
                minTargetAmount
            );
            
            emit TokenSwappedForBill(
                billId,
                paymentToken,
                targetToken,
                paymentAmount,
                targetAmount,
                msg.sender
            );
        }
        
        // Send the target token cross-chain
        _sendSwappedTokenCrossChain(
            billId,
            destinationChain,
            destinationAddress,
            targetAmount,
            targetTokenSymbol
        );
        
        emit SwapAndCrossChainSent(
            billId,
            paymentToken,
            targetTokenSymbol,
            paymentAmount,
            targetAmount,
            destinationChain
        );
    }
    
    /**
     * @dev Internal function to swap tokens via 1inch
     */
    function _swapTokensViaOneInch(
        address fromToken,
        address toToken,
        uint256 amount,
        bytes calldata swapData,
        uint256 minAmount
    ) internal returns (uint256 amountOut) {
        address router = oneInchRouters[block.chainid];
        if (router == address(0)) revert OneInchRouterNotSet();
        
        // Transfer tokens from user to this contract
        IERC20(fromToken).safeTransferFrom(msg.sender, address(this), amount);
        
        // Record balance before swap
        uint256 balanceBefore = IERC20(toToken).balanceOf(address(this));
        
        // Approve 1inch router to spend fromToken
        IERC20(fromToken).forceApprove(router, amount);
        
        // Execute the swap
        (bool success,) = router.call(swapData);
        if (!success) revert SwapFailed();
        
        // Calculate amount received
        uint256 balanceAfter = IERC20(toToken).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        
        if (amountOut < minAmount) revert InsufficientSwapOutput();
        
        return amountOut;
    }
    
    /**
     * @dev Internal function to send swapped tokens cross-chain
     */
    function _sendSwappedTokenCrossChain(
        bytes32 billId,
        string calldata destinationChain,
        address destinationAddress,
        uint256 amount,
        string calldata symbol
    ) internal {
        // Approve gateway to spend tokens
        address tokenAddress = gatewayWithToken().tokenAddresses(symbol);
        IERC20(tokenAddress).forceApprove(address(gatewayWithToken()), amount);
        
        // Prepare payload
        bytes memory payload = abi.encode(
            CROSS_CHAIN_PAYMENT,
            billId,
            msg.sender,
            amount,
            block.timestamp
        );
        
        // Pay for gas
        uint256 gasFee = msg.value;
        if (gasFee == 0) revert InsufficientGasFee();
        
        gasService.payNativeGasForContractCallWithToken{value: gasFee}(
            address(this),
            destinationChain,
            _addressToString(destinationAddress),
            payload,
            symbol,
            amount,
            msg.sender
        );
        
        // Send tokens cross-chain
        gatewayWithToken().callContractWithToken(
            destinationChain,
            _addressToString(destinationAddress),
            payload,
            symbol,
            amount
        );
        
        emit CrossChainPaymentInitiated(
            billId,
            destinationChain,
            destinationAddress,
            amount,
            symbol
        );
    }
    
    /**
     * @dev Update 1inch router address for a chain (only owner)
     */
    function updateOneInchRouter(uint256 chainId, address router) external onlyOwner {
        oneInchRouters[chainId] = router;
    }
    
    /**
     * @dev Get quote from 1inch (this should be called off-chain)
     * @dev In practice, you'd call 1inch API to get the swap data and quote
     */
    function getOneInchQuote(
        address fromToken,
        address toToken,
        uint256 amount
    ) external view returns (uint256 estimatedOut) {
        // This is a placeholder - actual implementation should call 1inch API
        // For now, return a simple ratio based estimation
        return (amount * 95) / 100; // Assume 5% slippage for example
    }
}
