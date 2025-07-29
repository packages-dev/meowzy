// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./MerkleVerifier.sol";
import "./PaymentManager.sol";
import "./CrossChainBridge.sol";

/**
 * @title CrossChainBillSplitter
 * @dev Main coordinator contract for cross-chain bill splitting
 * @notice Manages groups, bills, and coordinates cross-chain payments
 */
contract CrossChainBillSplitter is AccessControl, ReentrancyGuard, Pausable {
    
    // Role definitions
    bytes32 public constant GROUP_ADMIN_ROLE = keccak256("GROUP_ADMIN_ROLE");
    bytes32 public constant BILL_CREATOR_ROLE = keccak256("BILL_CREATOR_ROLE");
    bytes32 public constant DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");
    
    // Events
    event GroupCreated(bytes32 indexed groupId, address indexed creator, string name);
    event MemberAdded(bytes32 indexed groupId, address indexed member, address indexed addedBy);
    event MemberRemoved(bytes32 indexed groupId, address indexed member, address indexed removedBy);
    event BillCreated(bytes32 indexed billId, bytes32 indexed groupId, address indexed creator, uint256 amount);
    event BillSettled(bytes32 indexed billId, uint256 totalSettled);
    event CrossChainBillCreated(bytes32 indexed billId, string[] chains, uint256[] amounts);
    event EmergencyStop(address indexed admin, string reason);
    event GroupPermissionUpdated(bytes32 indexed groupId, address indexed member, bool canCreateBills);
    
    // Errors
    error GroupNotFound();
    error BillNotFound();
    error UnauthorizedAccess();
    error InvalidGroupConfiguration();
    error InvalidBillAmount();
    error MemberAlreadyExists();
    error MemberNotFound();
    error GroupSizeLimitExceeded();
    error BillAlreadySettled();
    error InsufficientPermissions();
    
    // Structs
    struct Group {
        bytes32 groupId;
        string name;
        string description;
        address creator;
        address[] members;
        mapping(address => bool) isMember;
        mapping(address => bool) canCreateBills;
        uint256 createdAt;
        uint256 totalBills;
        uint256 totalSettled;
        bool active;
    }
    
    struct Bill {
        bytes32 billId;
        bytes32 groupId;
        address creator;
        string description;
        uint256 totalAmount;
        address paymentToken;
        MerkleVerifier.SplitType splitType;
        address[] members;
        uint256[] memberAmounts;
        uint256 createdAt;
        uint256 dueDate;
        bool crossChain;
        string[] participatingChains;
        mapping(string => uint256) chainAmounts;
        bool settled;
        bool disputed;
    }
    
    // State variables
    MerkleVerifier public immutable merkleVerifier;
    PaymentManager public immutable paymentManager;
    CrossChainBridge public immutable crossChainBridge;
    
    // Storage
    mapping(bytes32 => Group) public groups;
    mapping(bytes32 => Bill) public bills;
    mapping(address => bytes32[]) public userGroups;
    mapping(address => bytes32[]) public userBills;
    mapping(bytes32 => bytes32[]) public groupBills;
    
    // Configuration
    uint256 public constant MAX_GROUP_SIZE = 50;
    uint256 public constant MAX_BILL_DURATION = 30 days;
    uint256 public totalGroups;
    uint256 public totalBills;
    
    // Arrays for enumeration
    bytes32[] public allGroups;
    bytes32[] public allBills;
    
    constructor(
        address _merkleVerifier,
        address _paymentManager,
        address _crossChainBridge
    ) {
        merkleVerifier = MerkleVerifier(_merkleVerifier);
        paymentManager = PaymentManager(_paymentManager);
        crossChainBridge = CrossChainBridge(_crossChainBridge);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DISPUTE_RESOLVER_ROLE, msg.sender);
    }
    
    /**
     * @dev Create a new group for bill splitting
     * @param name Group name
     * @param description Group description
     * @param initialMembers Initial members to add to the group
     * @return groupId Unique identifier for the group
     */
    function createGroup(
        string calldata name,
        string calldata description,
        address[] calldata initialMembers
    ) external nonReentrant whenNotPaused returns (bytes32 groupId) {
        if (initialMembers.length > MAX_GROUP_SIZE) revert GroupSizeLimitExceeded();
        
        groupId = keccak256(abi.encodePacked(msg.sender, block.timestamp, totalGroups));
        
        Group storage group = groups[groupId];
        group.groupId = groupId;
        group.name = name;
        group.description = description;
        group.creator = msg.sender;
        group.createdAt = block.timestamp;
        group.active = true;
        
        // Add creator as first member with admin permissions
        group.members.push(msg.sender);
        group.isMember[msg.sender] = true;
        group.canCreateBills[msg.sender] = true;
        
        // Add initial members
        for (uint256 i = 0; i < initialMembers.length; i++) {
            address member = initialMembers[i];
            if (member != msg.sender && !group.isMember[member]) {
                group.members.push(member);
                group.isMember[member] = true;
                group.canCreateBills[member] = true; // Default permission
                userGroups[member].push(groupId);
            }
        }
        
        userGroups[msg.sender].push(groupId);
        allGroups.push(groupId);
        totalGroups++;
        
        // Grant group admin role to creator
        _grantRole(GROUP_ADMIN_ROLE, msg.sender);
        
        emit GroupCreated(groupId, msg.sender, name);
        
        return groupId;
    }
    
    /**
     * @dev Add a member to a group
     * @param groupId Group identifier
     * @param member Address to add
     */
    function addMember(
        bytes32 groupId,
        address member
    ) external nonReentrant whenNotPaused {
        Group storage group = groups[groupId];
        if (group.groupId == bytes32(0)) revert GroupNotFound();
        if (!group.isMember[msg.sender] || msg.sender != group.creator) {
            revert UnauthorizedAccess();
        }
        if (group.isMember[member]) revert MemberAlreadyExists();
        if (group.members.length >= MAX_GROUP_SIZE) revert GroupSizeLimitExceeded();
        
        group.members.push(member);
        group.isMember[member] = true;
        group.canCreateBills[member] = true; // Default permission
        userGroups[member].push(groupId);
        
        emit MemberAdded(groupId, member, msg.sender);
    }
    
    /**
     * @dev Remove a member from a group
     * @param groupId Group identifier
     * @param member Address to remove
     */
    function removeMember(
        bytes32 groupId,
        address member
    ) external nonReentrant whenNotPaused {
        Group storage group = groups[groupId];
        if (group.groupId == bytes32(0)) revert GroupNotFound();
        if (!group.isMember[msg.sender] || msg.sender != group.creator) {
            revert UnauthorizedAccess();
        }
        if (!group.isMember[member]) revert MemberNotFound();
        if (member == group.creator) revert UnauthorizedAccess(); // Cannot remove creator
        
        // Remove from members array
        for (uint256 i = 0; i < group.members.length; i++) {
            if (group.members[i] == member) {
                group.members[i] = group.members[group.members.length - 1];
                group.members.pop();
                break;
            }
        }
        
        group.isMember[member] = false;
        group.canCreateBills[member] = false;
        
        // Remove from user's groups
        bytes32[] storage memberGroups = userGroups[member];
        for (uint256 i = 0; i < memberGroups.length; i++) {
            if (memberGroups[i] == groupId) {
                memberGroups[i] = memberGroups[memberGroups.length - 1];
                memberGroups.pop();
                break;
            }
        }
        
        emit MemberRemoved(groupId, member, msg.sender);
    }
    
    /**
     * @dev Create a bill within a group
     * @param groupId Group identifier
     * @param description Bill description
     * @param totalAmount Total amount of the bill
     * @param paymentToken Token address for payments
     * @param splitType How to split the bill (EQUAL, PERCENTAGE, CUSTOM)
     * @param memberAmounts Amounts for each member (for PERCENTAGE/CUSTOM splits)
     * @param dueDate Payment due date
     * @return billId Unique identifier for the bill
     */
    function createBill(
        bytes32 groupId,
        string calldata description,
        uint256 totalAmount,
        address paymentToken,
        MerkleVerifier.SplitType splitType,
        uint256[] calldata memberAmounts,
        uint256 dueDate
    ) external nonReentrant whenNotPaused returns (bytes32 billId) {
        Group storage group = groups[groupId];
        if (group.groupId == bytes32(0)) revert GroupNotFound();
        if (!group.isMember[msg.sender] || !group.canCreateBills[msg.sender]) {
            revert UnauthorizedAccess();
        }
        if (totalAmount == 0) revert InvalidBillAmount();
        if (dueDate <= block.timestamp || dueDate > block.timestamp + MAX_BILL_DURATION) {
            revert InvalidBillAmount();
        }
        
        billId = keccak256(abi.encodePacked(groupId, msg.sender, block.timestamp, totalBills));
        
        Bill storage bill = bills[billId];
        bill.billId = billId;
        bill.groupId = groupId;
        bill.creator = msg.sender;
        bill.description = description;
        bill.totalAmount = totalAmount;
        bill.paymentToken = paymentToken;
        bill.splitType = splitType;
        
        // Copy members from group to bill
        for (uint256 i = 0; i < group.members.length; i++) {
            bill.members.push(group.members[i]);
        }
        
        bill.createdAt = block.timestamp;
        bill.dueDate = dueDate;
        
        // Validate and set member amounts based on split type
        if (splitType == MerkleVerifier.SplitType.EQUAL) {
            (uint256 splitAmount, uint256 remainder) = 
                merkleVerifier.calculateEqualSplit(totalAmount, group.members.length);
            
            for (uint256 i = 0; i < group.members.length; i++) {
                bill.memberAmounts.push(splitAmount + (i == 0 ? remainder : 0));
            }
        } else {
            if (memberAmounts.length != group.members.length) revert InvalidBillAmount();
            
            if (splitType == MerkleVerifier.SplitType.PERCENTAGE) {
                if (!merkleVerifier.validatePercentageSplit(memberAmounts)) {
                    revert InvalidBillAmount();
                }
                // Convert percentages to amounts
                for (uint256 i = 0; i < memberAmounts.length; i++) {
                    bill.memberAmounts.push((totalAmount * memberAmounts[i]) / 10000);
                }
            } else {
                // CUSTOM split - validate amounts sum to total
                uint256 sum = 0;
                for (uint256 i = 0; i < memberAmounts.length; i++) {
                    sum += memberAmounts[i];
                    bill.memberAmounts.push(memberAmounts[i]);
                }
                if (sum != totalAmount) revert InvalidBillAmount();
            }
        }
        
        // Create bill structure for Merkle verification (used for validation in production)
        // MerkleVerifier.BillStructure memory billStructure = MerkleVerifier.BillStructure({
        //     totalAmount: totalAmount,
        //     splitType: splitType,
        //     members: group.members,
        //     amounts: bill.memberAmounts,
        //     timestamp: block.timestamp,
        //     billId: billId
        // });
        
        // Generate Merkle proof and verify bill
        // Generate bill leaf for verification (unused in current implementation)
        // bytes32 billLeaf = merkleVerifier.generateBillLeaf(billStructure);
        // Note: In practice, you would generate the full Merkle tree and proof off-chain
        
        // Initialize payment collection
        paymentManager.initializeBillPayment(billId, totalAmount, paymentToken, msg.sender);
        
        // Update storage
        groupBills[groupId].push(billId);
        userBills[msg.sender].push(billId);
        allBills.push(billId);
        group.totalBills++;
        totalBills++;
        
        emit BillCreated(billId, groupId, msg.sender, totalAmount);
        
        return billId;
    }
    
    /**
     * @dev Create a cross-chain bill
     * @param groupId Group identifier
     * @param description Bill description
     * @param totalAmount Total amount of the bill
     * @param symbol Token symbol
     * @param participatingChains Array of participating chains
     * @param chainAmounts Array of amounts for each chain
     * @param dueDate Payment due date
     * @return billId Unique identifier for the bill
     */
    function createCrossChainBill(
        bytes32 groupId,
        string calldata description,
        uint256 totalAmount,
        string calldata symbol,
        string[] calldata participatingChains,
        uint256[] calldata chainAmounts,
        uint256 dueDate
    ) external nonReentrant whenNotPaused returns (bytes32 billId) {
        Group storage group = groups[groupId];
        if (group.groupId == bytes32(0)) revert GroupNotFound();
        if (!group.isMember[msg.sender] || !group.canCreateBills[msg.sender]) {
            revert UnauthorizedAccess();
        }
        if (totalAmount == 0) revert InvalidBillAmount();
        if (participatingChains.length != chainAmounts.length) revert InvalidBillAmount();
        
        billId = keccak256(abi.encodePacked(groupId, msg.sender, block.timestamp, totalBills));
        
        Bill storage bill = bills[billId];
        bill.billId = billId;
        bill.groupId = groupId;
        bill.creator = msg.sender;
        bill.description = description;
        bill.totalAmount = totalAmount;
        
        // Copy members from group to bill
        for (uint256 i = 0; i < group.members.length; i++) {
            bill.members.push(group.members[i]);
        }
        
        bill.createdAt = block.timestamp;
        bill.dueDate = dueDate;
        bill.crossChain = true;
        
        // Copy participating chains from calldata to storage
        for (uint256 i = 0; i < participatingChains.length; i++) {
            bill.participatingChains.push(participatingChains[i]);
        }
        
        // Set chain amounts
        for (uint256 i = 0; i < participatingChains.length; i++) {
            bill.chainAmounts[participatingChains[i]] = chainAmounts[i];
        }
        
        // Create cross-chain bill via bridge
        crossChainBridge.createCrossChainBill(
            billId,
            totalAmount,
            symbol,
            participatingChains,
            chainAmounts
        );
        
        // Update storage
        groupBills[groupId].push(billId);
        userBills[msg.sender].push(billId);
        allBills.push(billId);
        group.totalBills++;
        totalBills++;
        
        emit CrossChainBillCreated(billId, participatingChains, chainAmounts);
        
        return billId;
    }
    
    /**
     * @dev Settle a bill after all payments are collected
     * @param billId Bill identifier
     */
    function settleBill(bytes32 billId) external nonReentrant whenNotPaused {
        Bill storage bill = bills[billId];
        if (bill.billId == bytes32(0)) revert BillNotFound();
        if (bill.settled) revert BillAlreadySettled();
        
        // Settle payments through PaymentManager
        paymentManager.settlePayments(billId);
        
        bill.settled = true;
        
        // Update group stats
        Group storage group = groups[bill.groupId];
        group.totalSettled++;
        
        emit BillSettled(billId, bill.totalAmount);
    }
    
    /**
     * @dev Update member permissions in a group
     * @param groupId Group identifier
     * @param member Member address
     * @param canCreateBills Whether member can create bills
     */
    function updateMemberPermissions(
        bytes32 groupId,
        address member,
        bool canCreateBills
    ) external nonReentrant whenNotPaused {
        Group storage group = groups[groupId];
        if (group.groupId == bytes32(0)) revert GroupNotFound();
        if (msg.sender != group.creator) revert UnauthorizedAccess();
        if (!group.isMember[member]) revert MemberNotFound();
        
        group.canCreateBills[member] = canCreateBills;
        
        emit GroupPermissionUpdated(groupId, member, canCreateBills);
    }
    
    /**
     * @dev Get group information
     * @param groupId Group identifier
     * @return name Group name
     * @return description Group description
     * @return creator Group creator
     * @return members Array of member addresses
     * @return groupTotalBills Total bills created
     * @return groupTotalSettled Total bills settled
     * @return active Whether group is active
     */
    function getGroup(bytes32 groupId) external view returns (
        string memory name,
        string memory description,
        address creator,
        address[] memory members,
        uint256 groupTotalBills,
        uint256 groupTotalSettled,
        bool active
    ) {
        Group storage group = groups[groupId];
        return (
            group.name,
            group.description,
            group.creator,
            group.members,
            group.totalBills,
            group.totalSettled,
            group.active
        );
    }
    
    /**
     * @dev Get bill information
     * @param billId Bill identifier
     * @return groupId Group identifier
     * @return creator Bill creator
     * @return description Bill description
     * @return totalAmount Total bill amount
     * @return paymentToken Payment token address
     * @return members Array of member addresses
     * @return memberAmounts Array of member amounts
     * @return dueDate Payment due date
     * @return settled Whether bill is settled
     * @return crossChain Whether bill is cross-chain
     */
    function getBill(bytes32 billId) external view returns (
        bytes32 groupId,
        address creator,
        string memory description,
        uint256 totalAmount,
        address paymentToken,
        address[] memory members,
        uint256[] memory memberAmounts,
        uint256 dueDate,
        bool settled,
        bool crossChain
    ) {
        Bill storage bill = bills[billId];
        return (
            bill.groupId,
            bill.creator,
            bill.description,
            bill.totalAmount,
            bill.paymentToken,
            bill.members,
            bill.memberAmounts,
            bill.dueDate,
            bill.settled,
            bill.crossChain
        );
    }
    
    /**
     * @dev Get user's groups
     * @param user User address
     * @return groupIds Array of group identifiers
     */
    function getUserGroups(address user) external view returns (bytes32[] memory groupIds) {
        return userGroups[user];
    }
    
    /**
     * @dev Get user's bills
     * @param user User address
     * @return billIds Array of bill identifiers
     */
    function getUserBills(address user) external view returns (bytes32[] memory billIds) {
        return userBills[user];
    }
    
    /**
     * @dev Get group's bills
     * @param groupId Group identifier
     * @return billIds Array of bill identifiers
     */
    function getGroupBills(bytes32 groupId) external view returns (bytes32[] memory billIds) {
        return groupBills[groupId];
    }
    
    /**
     * @dev Check if user is member of a group
     * @param groupId Group identifier
     * @param user User address
     * @return isMember Whether user is a member
     */
    function isGroupMember(bytes32 groupId, address user) external view returns (bool isMember) {
        return groups[groupId].isMember[user];
    }
    
    /**
     * @dev Check if user can create bills in a group
     * @param groupId Group identifier
     * @param user User address
     * @return canCreate Whether user can create bills
     */
    function canUserCreateBills(bytes32 groupId, address user) external view returns (bool canCreate) {
        return groups[groupId].canCreateBills[user];
    }
    
    /**
     * @dev Get all groups (paginated)
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return groupIds Array of group identifiers
     */
    function getAllGroups(uint256 offset, uint256 limit) 
        external 
        view 
        returns (bytes32[] memory groupIds) 
    {
        if (offset >= allGroups.length) {
            return new bytes32[](0);
        }
        
        uint256 end = offset + limit;
        if (end > allGroups.length) {
            end = allGroups.length;
        }
        
        groupIds = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            groupIds[i - offset] = allGroups[i];
        }
        
        return groupIds;
    }
    
    /**
     * @dev Emergency stop function
     * @param reason Reason for emergency stop
     */
    function emergencyStop(string calldata reason) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
        emit EmergencyStop(msg.sender, reason);
    }
    
    /**
     * @dev Resume operations
     */
    function resume() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Get contract statistics
     * @return totalGroups Total number of groups
     * @return totalBills Total number of bills
     */
    function getStats() external view returns (uint256, uint256) {
        return (totalGroups, totalBills);
    }
}
