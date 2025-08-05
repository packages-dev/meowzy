// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AtomicSwapManager
 * @dev Implementation of Hash Time Lock Contracts (HTLC) for atomic swaps
 * @notice Enables trustless cross-chain token swaps between users
 */
contract AtomicSwapManager is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    
    // Events
    event SwapInitiated(
        bytes32 indexed swapId,
        address indexed initiator,
        address indexed participant,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bytes32 hashLock,
        uint256 timelock
    );
    
    event SwapParticipated(
        bytes32 indexed swapId,
        address indexed participant,
        uint256 participantTimelock
    );
    
    event SwapRedeemed(
        bytes32 indexed swapId,
        address indexed redeemer,
        bytes32 secret
    );
    
    event SwapRefunded(
        bytes32 indexed swapId,
        address indexed refundee
    );
    
    // Errors
    error SwapNotFound();
    error SwapAlreadyExists();
    error SwapAlreadyParticipated();
    error SwapAlreadyRedeemed();
    error SwapAlreadyRefunded();
    error InvalidSecret();
    error TimelockNotExpired();
    error TimelockExpired();
    error UnauthorizedParticipant();
    error InvalidTimelock();
    
    // Swap states
    enum SwapState {
        Invalid,
        Initiated,
        Participated,
        Redeemed,
        Refunded
    }
    
    // Swap structure
    struct AtomicSwap {
        bytes32 swapId;
        address initiator;
        address participant;
        address tokenA;
        uint256 amountA;
        address tokenB;
        uint256 amountB;
        bytes32 hashLock;
        uint256 initiatorTimelock;
        uint256 participantTimelock;
        SwapState state;
        uint256 createdAt;
    }
    
    // Storage
    mapping(bytes32 => AtomicSwap) public swaps;
    mapping(address => bytes32[]) public userSwaps;
    bytes32[] public allSwapIds;
    
    // Configuration
    uint256 public minimumTimelock = 1 hours;
    uint256 public maximumTimelock = 48 hours;
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Initiate an atomic swap
     * @param swapId Unique identifier for the swap
     * @param participant Address of the swap counterparty
     * @param tokenA Token that initiator is offering
     * @param amountA Amount of tokenA
     * @param tokenB Token that participant should offer
     * @param amountB Amount of tokenB expected
     * @param hashLock Hash of the secret
     * @param timelock Timelock for the swap (in seconds from now)
     */
    function initiateSwap(
        bytes32 swapId,
        address participant,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bytes32 hashLock,
        uint256 timelock
    ) external nonReentrant whenNotPaused {
        if (swaps[swapId].state != SwapState.Invalid) revert SwapAlreadyExists();
        if (participant == msg.sender) revert UnauthorizedParticipant();
        if (timelock < minimumTimelock || timelock > maximumTimelock) revert InvalidTimelock();
        
        uint256 initiatorTimelock = block.timestamp + timelock;
        
        // Transfer tokens from initiator to this contract
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        
        // Create swap
        swaps[swapId] = AtomicSwap({
            swapId: swapId,
            initiator: msg.sender,
            participant: participant,
            tokenA: tokenA,
            amountA: amountA,
            tokenB: tokenB,
            amountB: amountB,
            hashLock: hashLock,
            initiatorTimelock: initiatorTimelock,
            participantTimelock: 0,
            state: SwapState.Initiated,
            createdAt: block.timestamp
        });
        
        // Track swaps
        userSwaps[msg.sender].push(swapId);
        userSwaps[participant].push(swapId);
        allSwapIds.push(swapId);
        
        emit SwapInitiated(
            swapId,
            msg.sender,
            participant,
            tokenA,
            amountA,
            tokenB,
            amountB,
            hashLock,
            initiatorTimelock
        );
    }
    
    /**
     * @dev Participate in an atomic swap
     * @param swapId The swap identifier
     * @param timelock Timelock for the participation (must be less than initiator's timelock)
     */
    function participateSwap(
        bytes32 swapId,
        uint256 timelock
    ) external nonReentrant whenNotPaused {
        AtomicSwap storage swap = swaps[swapId];
        
        if (swap.state != SwapState.Initiated) revert SwapNotFound();
        if (msg.sender != swap.participant) revert UnauthorizedParticipant();
        if (block.timestamp >= swap.initiatorTimelock) revert TimelockExpired();
        
        uint256 participantTimelock = block.timestamp + timelock;
        if (participantTimelock >= swap.initiatorTimelock) revert InvalidTimelock();
        
        // Transfer tokens from participant to this contract
        IERC20(swap.tokenB).safeTransferFrom(msg.sender, address(this), swap.amountB);
        
        // Update swap
        swap.participantTimelock = participantTimelock;
        swap.state = SwapState.Participated;
        
        emit SwapParticipated(swapId, msg.sender, participantTimelock);
    }
    
    /**
     * @dev Redeem an atomic swap with the secret
     * @param swapId The swap identifier
     * @param secret The secret that hashes to hashLock
     */
    function redeemSwap(bytes32 swapId, bytes32 secret) external nonReentrant {
        AtomicSwap storage swap = swaps[swapId];
        
        if (swap.state != SwapState.Participated) revert SwapNotFound();
        if (keccak256(abi.encodePacked(secret)) != swap.hashLock) revert InvalidSecret();
        
        address redeemer;
        address tokenToTransfer;
        uint256 amountToTransfer;
        
        if (msg.sender == swap.initiator) {
            // Initiator redeems participant's tokens
            if (block.timestamp >= swap.participantTimelock) revert TimelockExpired();
            redeemer = swap.initiator;
            tokenToTransfer = swap.tokenB;
            amountToTransfer = swap.amountB;
        } else if (msg.sender == swap.participant) {
            // Participant redeems initiator's tokens
            if (block.timestamp >= swap.initiatorTimelock) revert TimelockExpired();
            redeemer = swap.participant;
            tokenToTransfer = swap.tokenA;
            amountToTransfer = swap.amountA;
        } else {
            revert UnauthorizedParticipant();
        }
        
        // Update state
        swap.state = SwapState.Redeemed;
        
        // Transfer tokens
        IERC20(tokenToTransfer).safeTransfer(redeemer, amountToTransfer);
        
        emit SwapRedeemed(swapId, redeemer, secret);
    }
    
    /**
     * @dev Refund a swap after timelock expiry
     * @param swapId The swap identifier
     */
    function refundSwap(bytes32 swapId) external nonReentrant {
        AtomicSwap storage swap = swaps[swapId];
        
        if (swap.state == SwapState.Invalid || swap.state == SwapState.Redeemed || swap.state == SwapState.Refunded) {
            revert SwapNotFound();
        }
        
        address refundee;
        address tokenToRefund;
        uint256 amountToRefund;
        
        if (msg.sender == swap.initiator && block.timestamp >= swap.initiatorTimelock) {
            // Refund initiator's tokens
            refundee = swap.initiator;
            tokenToRefund = swap.tokenA;
            amountToRefund = swap.amountA;
        } else if (msg.sender == swap.participant && 
                   swap.state == SwapState.Participated && 
                   block.timestamp >= swap.participantTimelock) {
            // Refund participant's tokens
            refundee = swap.participant;
            tokenToRefund = swap.tokenB;
            amountToRefund = swap.amountB;
        } else {
            revert TimelockNotExpired();
        }
        
        // Update state
        swap.state = SwapState.Refunded;
        
        // Transfer tokens back
        IERC20(tokenToRefund).safeTransfer(refundee, amountToRefund);
        
        emit SwapRefunded(swapId, refundee);
    }
    
    /**
     * @dev Get all swaps for a user
     * @param user The user address
     * @return Array of swap IDs
     */
    function getUserSwaps(address user) external view returns (bytes32[] memory) {
        return userSwaps[user];
    }
    
    /**
     * @dev Get all active swaps
     * @return Array of swap IDs
     */
    function getAllSwaps() external view returns (bytes32[] memory) {
        return allSwapIds;
    }
    
    /**
     * @dev Check if a secret is valid for a swap
     * @param swapId The swap identifier
     * @param secret The secret to check
     * @return bool indicating if secret is valid
     */
    function verifySecret(bytes32 swapId, bytes32 secret) external view returns (bool) {
        return keccak256(abi.encodePacked(secret)) == swaps[swapId].hashLock;
    }
    
    /**
     * @dev Generate a hash lock from a secret
     * @param secret The secret
     * @return bytes32 hash of the secret
     */
    function generateHashLock(bytes32 secret) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(secret));
    }
    
    /**
     * @dev Update timelock limits (only owner)
     */
    function updateTimelockLimits(uint256 _minimum, uint256 _maximum) external onlyOwner {
        minimumTimelock = _minimum;
        maximumTimelock = _maximum;
    }
    
    /**
     * @dev Emergency pause (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
