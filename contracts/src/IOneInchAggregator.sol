// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOneInchAggregator
 * @dev Interface for 1inch aggregation router
 */
interface IOneInchAggregator {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }
    
    function swap(
        address executor,
        SwapDescription calldata desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (uint256 returnAmount, uint256 spentAmount, uint256 gasLeft);
    
    function unoswap(
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        bytes32[] calldata pools
    ) external returns (uint256 returnAmount);
}
