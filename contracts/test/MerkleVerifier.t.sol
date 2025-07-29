// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MerkleVerifier.sol";

contract MerkleVerifierTest is Test {
    MerkleVerifier public merkleVerifier;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        vm.prank(owner);
        merkleVerifier = new MerkleVerifier();
    }
    
    function testCalculateEqualSplit() public view {
        // Test equal split
        (uint256 splitAmount, uint256 remainder) = merkleVerifier.calculateEqualSplit(1000, 3);
        assertEq(splitAmount, 333);
        assertEq(remainder, 1);
        
        // Test perfect division
        (splitAmount, remainder) = merkleVerifier.calculateEqualSplit(1000, 4);
        assertEq(splitAmount, 250);
        assertEq(remainder, 0);
        
        // Test edge case with 0 members
        (splitAmount, remainder) = merkleVerifier.calculateEqualSplit(1000, 0);
        assertEq(splitAmount, 0);
        assertEq(remainder, 1000);
    }
    
    function testValidatePercentageSplit() public view {
        // Test valid percentage split (100%)
        uint256[] memory validPercentages = new uint256[](3);
        validPercentages[0] = 3000; // 30%
        validPercentages[1] = 3000; // 30%
        validPercentages[2] = 4000; // 40%
        
        assertTrue(merkleVerifier.validatePercentageSplit(validPercentages));
        
        // Test invalid percentage split (not 100%)
        uint256[] memory invalidPercentages = new uint256[](3);
        invalidPercentages[0] = 3000; // 30%
        invalidPercentages[1] = 3000; // 30%
        invalidPercentages[2] = 3000; // 30% (total = 90%)
        
        assertFalse(merkleVerifier.validatePercentageSplit(invalidPercentages));
    }
    
    function testGenerateBillLeaf() public view {
        address[] memory members = new address[](2);
        members[0] = user1;
        members[1] = user2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500;
        amounts[1] = 500;
        
        MerkleVerifier.BillStructure memory bill = MerkleVerifier.BillStructure({
            totalAmount: 1000,
            splitType: MerkleVerifier.SplitType.EQUAL,
            members: members,
            amounts: amounts,
            timestamp: block.timestamp,
            billId: bytes32("test-bill-1")
        });
        
        bytes32 leaf = merkleVerifier.generateBillLeaf(bill);
        assertNotEq(leaf, bytes32(0));
        
        // Same bill should generate same leaf
        bytes32 leaf2 = merkleVerifier.generateBillLeaf(bill);
        assertEq(leaf, leaf2);
    }
    
    function testInvalidateBill() public {
        bytes32 testRoot = keccak256("test-root");
        
        // Only owner can invalidate
        vm.expectRevert();
        vm.prank(user1);
        merkleVerifier.invalidateBill(testRoot);
        
        // Owner can invalidate
        vm.prank(owner);
        merkleVerifier.invalidateBill(testRoot);
        
        // Should be marked as not verified
        assertFalse(merkleVerifier.isBillVerified(testRoot));
    }
    
    function testRevertOnInvalidBillStructure() public {
        // Test with empty bill ID
        address[] memory members = new address[](2);
        members[0] = user1;
        members[1] = user2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500;
        amounts[1] = 500;
        
        MerkleVerifier.BillStructure memory invalidBill = MerkleVerifier.BillStructure({
            totalAmount: 1000,
            splitType: MerkleVerifier.SplitType.EQUAL,
            members: members,
            amounts: amounts,
            timestamp: block.timestamp,
            billId: bytes32(0) // Invalid bill ID
        });
        
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes memory billData = abi.encode(invalidBill);
        
        vm.expectRevert(MerkleVerifier.InvalidMerkleRoot.selector);
        merkleVerifier.verifyBillStructure(emptyProof, bytes32(0), billData);
    }
    
    function testMaxGroupSizeLimit() public {
        address[] memory tooManyMembers = new address[](101); // Exceeds MAX_GROUP_SIZE
        for (uint256 i = 0; i < 101; i++) {
            tooManyMembers[i] = makeAddr(string(abi.encodePacked("user", i)));
        }
        
        uint256[] memory amounts = new uint256[](101);
        for (uint256 i = 0; i < 101; i++) {
            amounts[i] = 10;
        }
        
        MerkleVerifier.BillStructure memory oversizedBill = MerkleVerifier.BillStructure({
            totalAmount: 1010,
            splitType: MerkleVerifier.SplitType.CUSTOM,
            members: tooManyMembers,
            amounts: amounts,
            timestamp: block.timestamp,
            billId: bytes32("oversized-bill")
        });
        
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes memory billData = abi.encode(oversizedBill);
        bytes32 root = keccak256("test-root");
        
        vm.expectRevert(MerkleVerifier.InvalidProof.selector);
        merkleVerifier.verifyBillStructure(emptyProof, root, billData);
    }
}
