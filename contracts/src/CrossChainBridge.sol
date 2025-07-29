// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "axelar-gmp-sdk-solidity/executable/AxelarExecutableWithToken.sol";
import "axelar-gmp-sdk-solidity/interfaces/IAxelarGateway.sol";
import "axelar-gmp-sdk-solidity/interfaces/IAxelarGasService.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title CrossChainBridge
 * @dev Cross-chain payment settlement using Axelar Network
 * @notice Enables bill splitting across different blockchain networks
 */
contract CrossChainBridge is AxelarExecutableWithToken, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Events
    event CrossChainPaymentInitiated(
        bytes32 indexed billId,
        string destinationChain,
        address destinationAddress,
        uint256 amount,
        string symbol
    );
    event CrossChainPaymentReceived(
        bytes32 indexed billId,
        string sourceChain,
        address sender,
        uint256 amount,
        string symbol
    );
    event BillSynchronized(bytes32 indexed billId, string[] chains);
    event CrossChainRefundIssued(bytes32 indexed billId, address recipient, uint256 amount);
    
    // Errors
    error InvalidChain();
    error InvalidAmount();
    error InvalidBillId();
    error UnauthorizedSender();
    error InsufficientGasFee();
    error CrossChainOperationFailed();
    error BillNotFound();
    
    // Structs
    struct CrossChainBill {
        bytes32 billId;
        address creator;
        uint256 totalAmount;
        string symbol;
        string[] participatingChains;
        mapping(string => uint256) chainAmounts;
        mapping(string => bool) chainSettled;
        bool fullySettled;
        uint256 createdAt;
    }
    
    struct PendingPayment {
        bytes32 billId;
        address payer;
        uint256 amount;
        string symbol;
        string sourceChain;
        uint256 timestamp;
        bool processed;
    }
    
    // State variables
    IAxelarGasService public immutable gasService;
    
    // Cross-chain bill tracking
    mapping(bytes32 => CrossChainBill) public crossChainBills;
    mapping(bytes32 => PendingPayment[]) public pendingPayments;
    mapping(string => bool) public supportedChains;
    mapping(string => address) public trustedRemotes;
    
    // Supported chains list
    string[] public supportedChainsList;
    
    // Message types for cross-chain communication
    bytes32 public constant CROSS_CHAIN_PAYMENT = keccak256("CROSS_CHAIN_PAYMENT");
    bytes32 public constant BILL_SYNCHRONIZATION = keccak256("BILL_SYNCHRONIZATION");
    bytes32 public constant SETTLEMENT_CONFIRMATION = keccak256("SETTLEMENT_CONFIRMATION");
    
    constructor(
        address _gateway,
        address _gasService
    ) AxelarExecutableWithToken(_gateway) Ownable(msg.sender) {
        gasService = IAxelarGasService(_gasService);
        
        // Initialize with common testnet chains
        _addSupportedChain("ethereum-sepolia");
        _addSupportedChain("polygon-mumbai");
        _addSupportedChain("arbitrum-goerli");
    }
    
    /**
     * @dev Create a cross-chain bill
     * @param billId Unique identifier for the bill
     * @param totalAmount Total amount of the bill
     * @param symbol Token symbol for the bill
     * @param participatingChains Array of chain names that will participate
     * @param chainAmounts Array of amounts for each participating chain
     */
    function createCrossChainBill(
        bytes32 billId,
        uint256 totalAmount,
        string calldata symbol,
        string[] calldata participatingChains,
        uint256[] calldata chainAmounts
    ) external nonReentrant whenNotPaused {
        if (billId == bytes32(0)) revert InvalidBillId();
        if (totalAmount == 0) revert InvalidAmount();
        if (participatingChains.length != chainAmounts.length) revert InvalidAmount();
        if (crossChainBills[billId].billId != bytes32(0)) revert InvalidBillId();
        
        // Validate participating chains
        uint256 totalChainAmounts = 0;
        for (uint256 i = 0; i < participatingChains.length; i++) {
            if (!supportedChains[participatingChains[i]]) revert InvalidChain();
            totalChainAmounts += chainAmounts[i];
        }
        
        if (totalChainAmounts != totalAmount) revert InvalidAmount();
        
        // Create cross-chain bill
        CrossChainBill storage bill = crossChainBills[billId];
        bill.billId = billId;
        bill.creator = msg.sender;
        bill.totalAmount = totalAmount;
        bill.symbol = symbol;
        bill.createdAt = block.timestamp;
        
        // Copy participating chains from calldata to storage
        for (uint256 i = 0; i < participatingChains.length; i++) {
            bill.participatingChains.push(participatingChains[i]);
            bill.chainAmounts[participatingChains[i]] = chainAmounts[i];
        }
        
        // Synchronize bill across all participating chains
        _synchronizeBillAcrossChains(billId, participatingChains);
        
        emit BillSynchronized(billId, participatingChains);
    }
    
    /**
     * @dev Make a cross-chain payment
     * @param billId Bill identifier
     * @param destinationChain Target chain for payment
     * @param destinationAddress Target address on destination chain
     * @param amount Payment amount
     * @param symbol Token symbol
     */
    function makeCrossChainPayment(
        bytes32 billId,
        string calldata destinationChain,
        address destinationAddress,
        uint256 amount,
        string calldata symbol
    ) external payable nonReentrant whenNotPaused {
        if (billId == bytes32(0)) revert InvalidBillId();
        if (!supportedChains[destinationChain]) revert InvalidChain();
        if (amount == 0) revert InvalidAmount();
        if (trustedRemotes[destinationChain] == address(0)) revert InvalidChain();
        
        // Prepare cross-chain message
        bytes memory payload = abi.encode(
            CROSS_CHAIN_PAYMENT,
            billId,
            msg.sender,
            amount,
            symbol,
            block.timestamp
        );
        
        // Calculate gas fee for cross-chain call
        uint256 gasFee = msg.value;
        if (gasFee == 0) revert InsufficientGasFee();
        
        // Send cross-chain message
        gasService.payNativeGasForContractCall{value: gasFee}(
            address(this),
            destinationChain,
            _addressToString(trustedRemotes[destinationChain]),
            payload,
            msg.sender
        );
        
        gateway().callContract(
            destinationChain,
            _addressToString(trustedRemotes[destinationChain]),
            payload
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
     * @dev Send tokens cross-chain for bill payment
     * @param billId Bill identifier
     * @param destinationChain Target chain
     * @param destinationAddress Target address
     * @param amount Amount to send
     * @param symbol Token symbol
     */
    function sendTokenCrossChain(
        bytes32 billId,
        string calldata destinationChain,
        address destinationAddress,
        uint256 amount,
        string calldata symbol
    ) external payable nonReentrant whenNotPaused {
        if (billId == bytes32(0)) revert InvalidBillId();
        if (!supportedChains[destinationChain]) revert InvalidChain();
        if (amount == 0) revert InvalidAmount();
        
        // Get token address from symbol
        address tokenAddress = gatewayWithToken().tokenAddresses(symbol);
        if (tokenAddress == address(0)) revert InvalidAmount();
        
        // Transfer tokens from user to this contract
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve gateway to spend tokens
        IERC20(tokenAddress).forceApprove(address(gatewayWithToken()), amount);
        
        // Prepare payload for the destination
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
        
        // Send tokens with message
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
     * @dev Execute cross-chain message from Axelar
     * @param sourceChain Source chain identifier
     * @param sourceAddress Source contract address
     * @param payload Message payload
     */
    function _execute(
        bytes32 /* commandId */,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        if (!supportedChains[sourceChain]) revert InvalidChain();
        if (trustedRemotes[sourceChain] != _stringToAddress(sourceAddress)) {
            revert UnauthorizedSender();
        }
        
        (bytes32 messageType) = abi.decode(payload, (bytes32));
        
        if (messageType == CROSS_CHAIN_PAYMENT) {
            _processCrossChainPayment(sourceChain, payload);
        } else if (messageType == BILL_SYNCHRONIZATION) {
            _processBillSynchronization(sourceChain, payload);
        } else if (messageType == SETTLEMENT_CONFIRMATION) {
            _processSettlementConfirmation(sourceChain, payload);
        }
    }
    
    /**
     * @dev Execute cross-chain message with token
     * @param sourceChain Source chain identifier
     * @param sourceAddress Source contract address
     * @param payload Message payload
     * @param tokenSymbol Token symbol
     * @param amount Token amount
     */
    function _executeWithToken(
        bytes32 /* commandId */,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal override {
        if (!supportedChains[sourceChain]) revert InvalidChain();
        if (trustedRemotes[sourceChain] != _stringToAddress(sourceAddress)) {
            revert UnauthorizedSender();
        }
        
        (bytes32 messageType, bytes32 billId, address sender, uint256 timestamp) = 
            abi.decode(payload, (bytes32, bytes32, address, uint256));
        
        if (messageType == CROSS_CHAIN_PAYMENT) {
            // Record the payment
            pendingPayments[billId].push(PendingPayment({
                billId: billId,
                payer: sender,
                amount: amount,
                symbol: tokenSymbol,
                sourceChain: sourceChain,
                timestamp: timestamp,
                processed: false
            }));
            
            emit CrossChainPaymentReceived(billId, sourceChain, sender, amount, tokenSymbol);
        }
    }
    
    /**
     * @dev Process cross-chain payment message
     * @param sourceChain Source chain identifier
     * @param payload Message payload
     */
    function _processCrossChainPayment(
        string calldata sourceChain,
        bytes calldata payload
    ) internal {
        (, bytes32 billId, address sender, uint256 amount, string memory symbol, uint256 timestamp) = 
            abi.decode(payload, (bytes32, bytes32, address, uint256, string, uint256));
        
        // Record the payment
        pendingPayments[billId].push(PendingPayment({
            billId: billId,
            payer: sender,
            amount: amount,
            symbol: symbol,
            sourceChain: sourceChain,
            timestamp: timestamp,
            processed: false
        }));
        
        emit CrossChainPaymentReceived(billId, sourceChain, sender, amount, symbol);
    }
    
    /**
     * @dev Process bill synchronization message
     * @param payload Message payload
     */
    function _processBillSynchronization(
        string calldata /* sourceChain */,
        bytes calldata payload
    ) internal {
        (, bytes32 billId, address creator, uint256 totalAmount, string memory symbol, 
         string[] memory participatingChains, uint256[] memory chainAmounts) = 
            abi.decode(payload, (bytes32, bytes32, address, uint256, string, string[], uint256[]));
        
        // Create or update local bill record
        CrossChainBill storage bill = crossChainBills[billId];
        if (bill.billId == bytes32(0)) {
            bill.billId = billId;
            bill.creator = creator;
            bill.totalAmount = totalAmount;
            bill.symbol = symbol;
            bill.participatingChains = participatingChains;
            bill.createdAt = block.timestamp;
            
            // Set chain amounts
            for (uint256 i = 0; i < participatingChains.length; i++) {
                bill.chainAmounts[participatingChains[i]] = chainAmounts[i];
            }
        }
    }
    
    /**
     * @dev Process settlement confirmation message
     * @param sourceChain Source chain identifier
     * @param payload Message payload
     */
    function _processSettlementConfirmation(
        string calldata sourceChain,
        bytes calldata payload
    ) internal {
        (, bytes32 billId, bool settled) = 
            abi.decode(payload, (bytes32, bytes32, bool));
        
        CrossChainBill storage bill = crossChainBills[billId];
        if (bill.billId != bytes32(0)) {
            bill.chainSettled[sourceChain] = settled;
            
            // Check if all chains are settled
            bool allSettled = true;
            for (uint256 i = 0; i < bill.participatingChains.length; i++) {
                if (!bill.chainSettled[bill.participatingChains[i]]) {
                    allSettled = false;
                    break;
                }
            }
            
            if (allSettled) {
                bill.fullySettled = true;
            }
        }
    }
    
    /**
     * @dev Synchronize bill across all participating chains
     * @param billId Bill identifier
     * @param participatingChains Array of participating chains
     */
    function _synchronizeBillAcrossChains(
        bytes32 billId,
        string[] memory participatingChains
    ) internal {
        CrossChainBill storage bill = crossChainBills[billId];
        
        // Prepare chain amounts array
        uint256[] memory chainAmounts = new uint256[](participatingChains.length);
        for (uint256 i = 0; i < participatingChains.length; i++) {
            chainAmounts[i] = bill.chainAmounts[participatingChains[i]];
        }
        
        bytes memory payload = abi.encode(
            BILL_SYNCHRONIZATION,
            billId,
            bill.creator,
            bill.totalAmount,
            bill.symbol,
            participatingChains,
            chainAmounts
        );
        
        // Send synchronization message to all participating chains
        for (uint256 i = 0; i < participatingChains.length; i++) {
            string memory chain = participatingChains[i];
            if (trustedRemotes[chain] != address(0)) {
                gateway().callContract(
                    chain,
                    _addressToString(trustedRemotes[chain]),
                    payload
                );
            }
        }
    }
    
    /**
     * @dev Add a supported chain
     * @param chainName Chain identifier
     */
    function addSupportedChain(string calldata chainName) external onlyOwner {
        _addSupportedChain(chainName);
    }
    
    /**
     * @dev Internal function to add supported chain
     * @param chainName Chain identifier
     */
    function _addSupportedChain(string memory chainName) internal {
        if (!supportedChains[chainName]) {
            supportedChains[chainName] = true;
            supportedChainsList.push(chainName);
        }
    }
    
    /**
     * @dev Set trusted remote contract for a chain
     * @param chainName Chain identifier
     * @param remoteAddress Remote contract address
     */
    function setTrustedRemote(
        string calldata chainName,
        address remoteAddress
    ) external onlyOwner {
        trustedRemotes[chainName] = remoteAddress;
    }
    
    /**
     * @dev Get pending payments for a bill
     * @param billId Bill identifier
     * @return payments Array of pending payments
     */
    function getPendingPayments(bytes32 billId) 
        external 
        view 
        returns (PendingPayment[] memory payments) 
    {
        return pendingPayments[billId];
    }
    
    /**
     * @dev Get supported chains
     * @return chains Array of supported chain names
     */
    function getSupportedChains() external view returns (string[] memory chains) {
        return supportedChainsList;
    }
    
    /**
     * @dev Convert address to string
     * @param addr Address to convert
     * @return String representation
     */
    function _addressToString(address addr) internal pure returns (string memory) {
        return _toHexString(uint256(uint160(addr)), 20);
    }
    
    /**
     * @dev Convert string to address
     * @param str String to convert
     * @return Address representation
     */
    function _stringToAddress(string memory str) internal pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address string");
        
        bytes memory addrBytes = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(_fromHexChar(uint8(strBytes[2 + i * 2])) * 16 + 
                                 _fromHexChar(uint8(strBytes[3 + i * 2])));
        }
        
        return address(uint160(bytes20(addrBytes)));
    }
    
    /**
     * @dev Convert uint to hex string
     * @param value Value to convert
     * @param length String length
     * @return Hex string
     */
    function _toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
    
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    
    /**
     * @dev Convert hex character to uint
     * @param char Hex character
     * @return Uint value
     */
    function _fromHexChar(uint8 char) internal pure returns (uint8) {
        if (char >= uint8(bytes1('0')) && char <= uint8(bytes1('9'))) {
            return char - uint8(bytes1('0'));
        }
        if (char >= uint8(bytes1('a')) && char <= uint8(bytes1('f'))) {
            return 10 + char - uint8(bytes1('a'));
        }
        if (char >= uint8(bytes1('A')) && char <= uint8(bytes1('F'))) {
            return 10 + char - uint8(bytes1('A'));
        }
        revert("Invalid hex character");
    }
    
    /**
     * @dev Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
