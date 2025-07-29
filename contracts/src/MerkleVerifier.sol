// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MerkleVerifier
 * @dev Gas-optimized Merkle proof verification for bill splitting
 * @notice Efficient verification of bill authenticity and member participation
 */
contract MerkleVerifier is Ownable, ReentrancyGuard {
    
    // Events
    event BillStructureVerified(bytes32 indexed merkleRoot, address indexed verifier);
    event BatchVerificationCompleted(bytes32[] indexed roots, uint256 verifiedCount);
    
    // Errors
    error InvalidProof();
    error InvalidMerkleRoot();
    error BatchSizeTooLarge();
    error InvalidBillStructure();
    
    // Constants
    uint256 public constant MAX_BATCH_SIZE = 50;
    uint256 public constant MAX_GROUP_SIZE = 100;
    
    // Bill splitting types
    enum SplitType {
        EQUAL,      // Equal split among all members
        PERCENTAGE, // Custom percentage for each member
        CUSTOM      // Custom amounts for each member
    }
    
    // Bill structure for verification
    struct BillStructure {
        uint256 totalAmount;
        SplitType splitType;
        address[] members;
        uint256[] amounts; // For PERCENTAGE and CUSTOM splits
        uint256 timestamp;
        bytes32 billId;
    }
    
    // Mapping to store verified bill structures
    mapping(bytes32 => bool) public verifiedBills;
    mapping(bytes32 => BillStructure) public billStructures;
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Verify a single bill structure using Merkle proof
     * @param proof Merkle proof array
     * @param root Merkle root of the bill structure
     * @param billData Encoded bill structure data
     * @return verified True if proof is valid
     */
    function verifyBillStructure(
        bytes32[] calldata proof,
        bytes32 root,
        bytes calldata billData
    ) external nonReentrant returns (bool verified) {
        if (root == bytes32(0)) revert InvalidMerkleRoot();
        
        // Create leaf hash from bill data
        bytes32 leaf = keccak256(billData);
        
        // Verify Merkle proof
        verified = MerkleProof.verify(proof, root, leaf);
        if (!verified) revert InvalidProof();
        
        // Decode and validate bill structure
        BillStructure memory bill = abi.decode(billData, (BillStructure));
        _validateBillStructure(bill);
        
        // Store verified bill
        verifiedBills[root] = true;
        billStructures[root] = bill;
        
        emit BillStructureVerified(root, msg.sender);
        
        return verified;
    }
    
    /**
     * @dev Batch verify multiple bill structures for gas efficiency
     * @param proofs Array of Merkle proofs
     * @param roots Array of Merkle roots
     * @param billDataArray Array of encoded bill data
     * @return verifiedCount Number of successfully verified bills
     */
    function batchVerifyBills(
        bytes32[][] calldata proofs,
        bytes32[] calldata roots,
        bytes[] calldata billDataArray
    ) external nonReentrant returns (uint256 verifiedCount) {
        uint256 batchSize = roots.length;
        if (batchSize > MAX_BATCH_SIZE) revert BatchSizeTooLarge();
        if (batchSize != proofs.length || batchSize != billDataArray.length) {
            revert InvalidBillStructure();
        }
        
        for (uint256 i = 0; i < batchSize; i++) {
            try this.verifyBillStructure(proofs[i], roots[i], billDataArray[i]) {
                verifiedCount++;
            } catch {
                // Continue with next verification if one fails
                continue;
            }
        }
        
        emit BatchVerificationCompleted(roots, verifiedCount);
        
        return verifiedCount;
    }
    
    /**
     * @dev Generate Merkle leaf for bill structure
     * @param bill Bill structure to hash
     * @return leaf Merkle leaf hash
     */
    function generateBillLeaf(BillStructure calldata bill) 
        external 
        pure 
        returns (bytes32 leaf) 
    {
        return keccak256(abi.encode(bill));
    }
    
    /**
     * @dev Check if a bill structure is verified
     * @param root Merkle root to check
     * @return verified True if bill is verified
     */
    function isBillVerified(bytes32 root) external view returns (bool verified) {
        return verifiedBills[root];
    }
    
    /**
     * @dev Get bill structure by merkle root
     * @param root Merkle root of the bill
     * @return bill Bill structure data
     */
    function getBillStructure(bytes32 root) 
        external 
        view 
        returns (BillStructure memory bill) 
    {
        return billStructures[root];
    }
    
    /**
     * @dev Calculate equal split amounts for a bill
     * @param totalAmount Total bill amount
     * @param memberCount Number of group members
     * @return splitAmount Amount each member pays
     * @return remainder Any remainder amount
     */
    function calculateEqualSplit(uint256 totalAmount, uint256 memberCount)
        external
        pure
        returns (uint256 splitAmount, uint256 remainder)
    {
        if (memberCount == 0) return (0, totalAmount);
        
        splitAmount = totalAmount / memberCount;
        remainder = totalAmount % memberCount;
        
        return (splitAmount, remainder);
    }
    
    /**
     * @dev Validate percentage splits sum to 100%
     * @param percentages Array of percentage values (in basis points, 10000 = 100%)
     * @return valid True if percentages sum to 100%
     */
    function validatePercentageSplit(uint256[] calldata percentages)
        external
        pure
        returns (bool valid)
    {
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            totalPercentage += percentages[i];
        }
        
        return totalPercentage == 10000; // 100% in basis points
    }
    
    /**
     * @dev Internal function to validate bill structure
     * @param bill Bill structure to validate
     */
    function _validateBillStructure(BillStructure memory bill) internal pure {
        if (bill.totalAmount == 0) revert InvalidBillStructure();
        if (bill.members.length == 0 || bill.members.length > MAX_GROUP_SIZE) {
            revert InvalidBillStructure();
        }
        if (bill.billId == bytes32(0)) revert InvalidBillStructure();
        
        // Validate split-specific requirements
        if (bill.splitType == SplitType.PERCENTAGE) {
            if (bill.amounts.length != bill.members.length) {
                revert InvalidBillStructure();
            }
            
            // Check percentages sum to 100%
            uint256 totalPercentage = 0;
            for (uint256 i = 0; i < bill.amounts.length; i++) {
                totalPercentage += bill.amounts[i];
            }
            if (totalPercentage != 10000) revert InvalidBillStructure();
            
        } else if (bill.splitType == SplitType.CUSTOM) {
            if (bill.amounts.length != bill.members.length) {
                revert InvalidBillStructure();
            }
            
            // Check custom amounts sum to total
            uint256 totalCustom = 0;
            for (uint256 i = 0; i < bill.amounts.length; i++) {
                totalCustom += bill.amounts[i];
            }
            if (totalCustom != bill.totalAmount) revert InvalidBillStructure();
        }
    }
    
    /**
     * @dev Emergency function to mark a bill as unverified (admin only)
     * @param root Merkle root to invalidate
     */
    function invalidateBill(bytes32 root) external onlyOwner {
        verifiedBills[root] = false;
        delete billStructures[root];
    }
}
