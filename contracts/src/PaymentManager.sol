// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./MerkleVerifier.sol";

/**
 * @title PaymentManager
 * @dev Multi-token payment processing with escrow and settlement
 * @notice Handles payments, refunds, and dispute resolution for bill splitting
 */
contract PaymentManager is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Events
    event PaymentMade(bytes32 indexed billId, address indexed payer, uint256 amount, address token);
    event PaymentSettled(bytes32 indexed billId, address indexed recipient, uint256 amount);
    event RefundIssued(bytes32 indexed billId, address indexed recipient, uint256 amount);
    event DisputeRaised(bytes32 indexed billId, address indexed challenger);
    event DisputeResolved(bytes32 indexed billId, bool approved);
    event EscrowReleased(bytes32 indexed billId, uint256 totalAmount);
    
    // Errors
    error InvalidBillId();
    error PaymentAlreadyMade();
    error InsufficientPayment();
    error BillNotVerified();
    error UnauthorizedAccess();
    error PaymentWindowClosed();
    error DisputeActive();
    error InvalidToken();
    error PriceFeedError();
    
    // Structs
    struct Payment {
        address payer;
        uint256 amount;
        address token;
        uint256 timestamp;
        bool settled;
        bool refunded;
    }
    
    struct BillPayment {
        bytes32 billId;
        uint256 totalCollected;
        uint256 totalRequired;
        address paymentToken;
        address payee; // Person who paid the bill initially
        uint256 paymentDeadline;
        bool fullyPaid;
        bool disputed;
        uint256 disputeDeadline;
        mapping(address => Payment) memberPayments;
        address[] paymentMembers;
    }
    
    struct DisputeInfo {
        address challenger;
        uint256 timestamp;
        string reason;
        bool resolved;
        bool approved;
    }
    
    // State variables
    MerkleVerifier public immutable merkleVerifier;
    
    // Supported tokens for payments
    mapping(address => bool) public supportedTokens;
    address[] public supportedTokenList;
    
    // Bill payments tracking
    mapping(bytes32 => BillPayment) public billPayments;
    mapping(bytes32 => DisputeInfo) public disputes;
    
    // Configuration
    uint256 public constant PAYMENT_WINDOW = 7 days;
    uint256 public constant DISPUTE_WINDOW = 3 days;
    uint256 public protocolFeeBps = 50; // 0.5%
    address public feeRecipient;
    
    // Price feed integration (can be extended with Chainlink)
    mapping(address => uint256) public tokenPrices; // Price in USD (18 decimals)
    
    constructor(
        address _merkleVerifier,
        address _feeRecipient
    ) Ownable(msg.sender) {
        merkleVerifier = MerkleVerifier(_merkleVerifier);
        feeRecipient = _feeRecipient;
        
        // Add ETH as supported token (address(0) represents ETH)
        supportedTokens[address(0)] = true;
        supportedTokenList.push(address(0));
    }
    
    /**
     * @dev Initialize a bill for payment collection
     * @param billId Unique identifier for the bill
     * @param totalRequired Total amount required to be collected
     * @param paymentToken Token address for payments (address(0) for ETH)
     * @param payee Address of the person who initially paid the bill
     */
    function initializeBillPayment(
        bytes32 billId,
        uint256 totalRequired,
        address paymentToken,
        address payee
    ) external nonReentrant whenNotPaused {
        if (billId == bytes32(0)) revert InvalidBillId();
        if (!merkleVerifier.isBillVerified(billId)) revert BillNotVerified();
        if (!supportedTokens[paymentToken]) revert InvalidToken();
        if (billPayments[billId].billId != bytes32(0)) revert PaymentAlreadyMade();
        
        BillPayment storage bill = billPayments[billId];
        bill.billId = billId;
        bill.totalRequired = totalRequired;
        bill.paymentToken = paymentToken;
        bill.payee = payee;
        bill.paymentDeadline = block.timestamp + PAYMENT_WINDOW;
        
        emit PaymentMade(billId, payee, totalRequired, paymentToken);
    }
    
    /**
     * @dev Make a payment towards a bill
     * @param billId Bill identifier
     * @param amount Amount to pay (should match required amount for the member)
     */
    function makePayment(
        bytes32 billId,
        uint256 amount
    ) external payable nonReentrant whenNotPaused {
        BillPayment storage bill = billPayments[billId];
        if (bill.billId == bytes32(0)) revert InvalidBillId();
        if (block.timestamp > bill.paymentDeadline) revert PaymentWindowClosed();
        if (bill.disputed) revert DisputeActive();
        if (bill.memberPayments[msg.sender].payer != address(0)) revert PaymentAlreadyMade();
        
        address token = bill.paymentToken;
        uint256 paymentAmount;
        
        if (token == address(0)) {
            // ETH payment
            paymentAmount = msg.value;
            if (paymentAmount != amount) revert InsufficientPayment();
        } else {
            // ERC20 payment
            if (msg.value > 0) revert InsufficientPayment();
            paymentAmount = amount;
            IERC20(token).safeTransferFrom(msg.sender, address(this), paymentAmount);
        }
        
        // Record payment
        bill.memberPayments[msg.sender] = Payment({
            payer: msg.sender,
            amount: paymentAmount,
            token: token,
            timestamp: block.timestamp,
            settled: false,
            refunded: false
        });
        
        bill.paymentMembers.push(msg.sender);
        bill.totalCollected += paymentAmount;
        
        // Check if bill is fully paid
        if (bill.totalCollected >= bill.totalRequired) {
            bill.fullyPaid = true;
        }
        
        emit PaymentMade(billId, msg.sender, paymentAmount, token);
    }
    
    /**
     * @dev Settle payments - transfer collected funds to the payee
     * @param billId Bill identifier
     */
    function settlePayments(bytes32 billId) external nonReentrant whenNotPaused {
        BillPayment storage bill = billPayments[billId];
        if (bill.billId == bytes32(0)) revert InvalidBillId();
        if (!bill.fullyPaid) revert InsufficientPayment();
        if (bill.disputed && block.timestamp <= bill.disputeDeadline) revert DisputeActive();
        
        uint256 totalAmount = bill.totalCollected;
        address token = bill.paymentToken;
        address payee = bill.payee;
        
        // Calculate protocol fee
        uint256 protocolFee = (totalAmount * protocolFeeBps) / 10000;
        uint256 payeeAmount = totalAmount - protocolFee;
        
        // Transfer payments
        if (token == address(0)) {
            // ETH transfers
            payable(payee).transfer(payeeAmount);
            if (protocolFee > 0) {
                payable(feeRecipient).transfer(protocolFee);
            }
        } else {
            // ERC20 transfers
            IERC20(token).safeTransfer(payee, payeeAmount);
            if (protocolFee > 0) {
                IERC20(token).safeTransfer(feeRecipient, protocolFee);
            }
        }
        
        // Mark payments as settled
        for (uint256 i = 0; i < bill.paymentMembers.length; i++) {
            address member = bill.paymentMembers[i];
            bill.memberPayments[member].settled = true;
        }
        
        emit PaymentSettled(billId, payee, payeeAmount);
        emit EscrowReleased(billId, totalAmount);
    }
    
    /**
     * @dev Raise a dispute for a bill
     * @param billId Bill identifier
     * @param reason Reason for the dispute
     */
    function raiseDispute(
        bytes32 billId,
        string calldata reason
    ) external whenNotPaused {
        BillPayment storage bill = billPayments[billId];
        if (bill.billId == bytes32(0)) revert InvalidBillId();
        if (bill.memberPayments[msg.sender].payer == address(0)) revert UnauthorizedAccess();
        if (bill.disputed) revert DisputeActive();
        
        bill.disputed = true;
        bill.disputeDeadline = block.timestamp + DISPUTE_WINDOW;
        
        disputes[billId] = DisputeInfo({
            challenger: msg.sender,
            timestamp: block.timestamp,
            reason: reason,
            resolved: false,
            approved: false
        });
        
        emit DisputeRaised(billId, msg.sender);
    }
    
    /**
     * @dev Resolve a dispute (admin function)
     * @param billId Bill identifier
     * @param approved Whether the dispute is approved (true = refund, false = settle)
     */
    function resolveDispute(
        bytes32 billId,
        bool approved
    ) external onlyOwner {
        BillPayment storage bill = billPayments[billId];
        DisputeInfo storage dispute = disputes[billId];
        
        if (!bill.disputed) revert DisputeActive();
        if (dispute.resolved) revert DisputeActive();
        
        dispute.resolved = true;
        dispute.approved = approved;
        bill.disputed = false;
        
        if (approved) {
            // Issue refunds to all members
            _issueRefunds(billId);
        }
        
        emit DisputeResolved(billId, approved);
    }
    
    /**
     * @dev Issue refunds to all members of a bill
     * @param billId Bill identifier
     */
    function _issueRefunds(bytes32 billId) internal {
        BillPayment storage bill = billPayments[billId];
        address token = bill.paymentToken;
        
        for (uint256 i = 0; i < bill.paymentMembers.length; i++) {
            address member = bill.paymentMembers[i];
            Payment storage payment = bill.memberPayments[member];
            
            if (!payment.refunded && payment.amount > 0) {
                payment.refunded = true;
                
                if (token == address(0)) {
                    payable(member).transfer(payment.amount);
                } else {
                    IERC20(token).safeTransfer(member, payment.amount);
                }
                
                emit RefundIssued(billId, member, payment.amount);
            }
        }
    }
    
    /**
     * @dev Add a supported payment token
     * @param token Token address
     */
    function addSupportedToken(address token) external onlyOwner {
        if (!supportedTokens[token]) {
            supportedTokens[token] = true;
            supportedTokenList.push(token);
        }
    }
    
    /**
     * @dev Remove a supported payment token
     * @param token Token address
     */
    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        
        // Remove from array
        for (uint256 i = 0; i < supportedTokenList.length; i++) {
            if (supportedTokenList[i] == token) {
                supportedTokenList[i] = supportedTokenList[supportedTokenList.length - 1];
                supportedTokenList.pop();
                break;
            }
        }
    }
    
    /**
     * @dev Update protocol fee (admin function)
     * @param newFeeBps New fee in basis points
     */
    function updateProtocolFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 1000, "Fee too high"); // Max 10%
        protocolFeeBps = newFeeBps;
    }
    
    /**
     * @dev Update fee recipient (admin function)
     * @param newRecipient New fee recipient address
     */
    function updateFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid address");
        feeRecipient = newRecipient;
    }
    
    /**
     * @dev Get payment details for a member
     * @param billId Bill identifier
     * @param member Member address
     * @return payment Payment details
     */
    function getMemberPayment(
        bytes32 billId,
        address member
    ) external view returns (Payment memory payment) {
        return billPayments[billId].memberPayments[member];
    }
    
    /**
     * @dev Get bill payment summary
     * @param billId Bill identifier
     * @return totalCollected Total amount collected
     * @return totalRequired Total amount required
     * @return fullyPaid Whether bill is fully paid
     * @return disputed Whether bill is disputed
     */
    function getBillSummary(bytes32 billId) external view returns (
        uint256 totalCollected,
        uint256 totalRequired,
        bool fullyPaid,
        bool disputed
    ) {
        BillPayment storage bill = billPayments[billId];
        return (
            bill.totalCollected,
            bill.totalRequired,
            bill.fullyPaid,
            bill.disputed
        );
    }
    
    /**
     * @dev Get all supported tokens
     * @return tokens Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory tokens) {
        return supportedTokenList;
    }
    
    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause function
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Emergency withdrawal function (admin only)
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}
