// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockOneInchRouter
 * @dev Mock implementation of 1inch router for testing
 */
contract MockOneInchRouter {
    using SafeERC20 for IERC20;
    
    // Exchange rates: token => targetToken => rate (in target token decimals per 1 unit of source token)
    mapping(address => mapping(address => uint256)) public exchangeRates;
    
    event MockSwap(
        address indexed fromToken,
        address indexed toToken,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );
    
    error InsufficientLiquidity();
    error InvalidSwapData();
    error SwapFailed();
    
    /**
     * @dev Set exchange rate between two tokens
     * @param fromToken Source token
     * @param toToken Target token
     * @param rate Exchange rate (how much toToken you get for 1 fromToken)
     */
    function setExchangeRate(address fromToken, address toToken, uint256 rate) external {
        exchangeRates[fromToken][toToken] = rate;
    }
    
    /**
     * @dev Generate swap data for testing
     * @param fromToken Source token
     * @param toToken Target token
     * @param amount Amount to swap
     * @return swapData Encoded swap data
     */
    function generateSwapData(
        address fromToken,
        address toToken,
        uint256 amount
    ) external pure returns (bytes memory swapData) {
        return abi.encode(fromToken, toToken, amount);
    }
    
    /**
     * @dev Mock swap function that handles the actual token exchange
     * @dev This function should be called with the encoded swap data
     */
    function swap(
        address, // executor (ignored in mock)
        bytes calldata swapData
    ) external returns (uint256 returnAmount) {
        // Decode swap data
        (address fromToken, address toToken, uint256 amount) = abi.decode(
            swapData,
            (address, address, uint256)
        );
        
        return _performSwap(fromToken, toToken, amount, msg.sender);
    }
    
    /**
     * @dev Alternative swap interface
     */
    function mockSwap(
        address fromToken,
        address toToken,
        uint256 amount,
        address recipient
    ) external returns (uint256 returnAmount) {
        return _performSwap(fromToken, toToken, amount, recipient);
    }
    
    /**
     * @dev Fallback function to handle arbitrary swap calls
     */
    fallback() external {
        // Extract function selector and data
        bytes4 selector = bytes4(msg.data[:4]);
        
        // Check if this is a swap call (we'll accept any 4-byte selector for simplicity)
        if (msg.data.length >= 4) {
            // Decode the swap parameters from calldata
            // This is a simplified approach - real 1inch has complex encoding
            if (msg.data.length >= 68) { // Minimum size for our encoded data
                // Skip the selector (first 4 bytes) and decode our parameters
                bytes memory data = msg.data[4:];
                (address fromToken, address toToken, uint256 amount) = abi.decode(
                    data,
                    (address, address, uint256)
                );
                
                uint256 amountOut = _performSwap(fromToken, toToken, amount, msg.sender);
                
                // Return the amount
                assembly {
                    let ptr := mload(0x40)
                    mstore(ptr, amountOut)
                    return(ptr, 32)
                }
            }
        }
        
        revert SwapFailed();
    }
    
    /**
     * @dev Internal function to perform the actual swap
     */
    function _performSwap(
        address fromToken,
        address toToken,
        uint256 amount,
        address recipient
    ) internal returns (uint256 amountOut) {
        uint256 rate = exchangeRates[fromToken][toToken];
        if (rate == 0) revert InsufficientLiquidity();
        
        // Calculate output amount based on exchange rate
        // Rate is in target token decimals per 1 unit of source token
        uint256 fromDecimals = _getTokenDecimals(fromToken);
        amountOut = (amount * rate) / (10**fromDecimals);
        
        // Check if we have enough liquidity
        uint256 ourBalance = IERC20(toToken).balanceOf(address(this));
        if (ourBalance < amountOut) revert InsufficientLiquidity();
        
        // Transfer tokens from user to this contract
        IERC20(fromToken).safeTransferFrom(recipient, address(this), amount);
        
        // Transfer target tokens to user
        IERC20(toToken).safeTransfer(recipient, amountOut);
        
        emit MockSwap(fromToken, toToken, amount, amountOut, recipient);
        
        return amountOut;
    }
    
    /**
     * @dev Get token decimals (simplified for testing)
     */
    function _getTokenDecimals(address token) internal view returns (uint256) {
        try IERC20Extended(token).decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return 18; // Default to 18 decimals
        }
    }
    
    /**
     * @dev Get expected output amount for a swap
     */
    function getExpectedOutput(
        address fromToken,
        address toToken,
        uint256 amount
    ) external view returns (uint256 amountOut) {
        uint256 rate = exchangeRates[fromToken][toToken];
        if (rate == 0) return 0;
        
        uint256 fromDecimals = _getTokenDecimals(fromToken);
        amountOut = (amount * rate) / (10**fromDecimals);
        
        return amountOut;
    }
}

// Interface for ERC20 metadata  
interface IERC20Extended {
    function decimals() external view returns (uint8);
}
