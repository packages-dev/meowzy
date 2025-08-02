// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CrossChainBridgeWithSwap.sol";
import "../src/MockERC20.sol";
import "../src/MockOneInchRouter.sol";

/**
 * @title CrossChainBridgeWithSwapTest
 * @dev Comprehensive tests for CrossChainBridge with 1inch integration
 */
contract CrossChainBridgeWithSwapTest is Test {
    CrossChainBridgeWithSwap public bridge;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public axlUSDC;
    MockOneInchRouter public oneInchRouter;
    
    address public owner = address(0x1);
    address public user = address(0x2);
    address public mockGateway = address(0x3);
    address public mockGasService = address(0x4);
    
    bytes32 public constant TEST_BILL_ID = keccak256("TEST_BILL_1");
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock tokens
        tokenA = new MockERC20("Token A", "TOKA", 18);
        tokenB = new MockERC20("Token B", "TOKB", 18);
        axlUSDC = new MockERC20("Axelar USDC", "axlUSDC", 6);
        
        // Deploy mock 1inch router
        oneInchRouter = new MockOneInchRouter();
        
        // Deploy bridge
        bridge = new CrossChainBridgeWithSwap(mockGateway, mockGasService);
        
        // Update 1inch router for current chain
        bridge.updateOneInchRouter(block.chainid, address(oneInchRouter));
        
        // Setup mock gateway to return token addresses
        vm.mockCall(
            mockGateway,
            abi.encodeWithSignature("tokenAddresses(string)", "axlUSDC"),
            abi.encode(address(axlUSDC))
        );
        
        // Mint tokens to user
        tokenA.mint(user, 1000 * 10**18);
        tokenB.mint(user, 1000 * 10**18);
        axlUSDC.mint(user, 1000 * 10**6);
        
        // Setup oneInch router with exchange rates
        oneInchRouter.setExchangeRate(address(tokenA), address(axlUSDC), 2000 * 10**6); // 1 TOKA = 2000 axlUSDC
        
        // Add liquidity to router
        tokenA.mint(address(oneInchRouter), 10000 * 10**18);
        axlUSDC.mint(address(oneInchRouter), 10000000 * 10**6); // 10M axlUSDC
        
        vm.stopPrank();
    }
    
    function testDeployment() public {
        assertEq(bridge.owner(), owner);
        assertEq(bridge.oneInchRouters(block.chainid), address(oneInchRouter));
        assertTrue(bridge.supportedChains("ethereum-sepolia"));
        assertTrue(bridge.supportedChains("polygon-mumbai"));
    }
    
    function testPayBillWithSwap_SameToken() public {
        vm.startPrank(user);
        
        uint256 paymentAmount = 100 * 10**6; // 100 axlUSDC
        
        // Approve bridge to spend tokens
        axlUSDC.approve(address(bridge), paymentAmount);
        
        // Mock the gateway calls to prevent reverts
        vm.mockCall(
            mockGasService,
            abi.encodeWithSignature(
                "payNativeGasForContractCallWithToken(address,string,string,bytes,string,uint256,address)"
            ),
            ""
        );
        
        vm.mockCall(
            mockGateway,
            abi.encodeWithSignature("callContractWithToken(string,string,bytes,string,uint256)"),
            ""
        );
        
        // Mock token approval for gateway
        vm.mockCall(
            address(axlUSDC),
            abi.encodeWithSignature("forceApprove(address,uint256)"),
            abi.encode(true)
        );
        
        // Pay bill with same token (no swap needed)
        bridge.payBillWithSwap{value: 0.01 ether}(
            TEST_BILL_ID,
            address(axlUSDC),
            paymentAmount,
            "axlUSDC",
            "polygon-mumbai", 
            address(0x123),
            "",  // No swap data needed
            paymentAmount // Same amount expected
        );
        
        vm.stopPrank();
    }
    
    function testGetOneInchQuote() public {
        uint256 amount = 1 * 10**18;
        uint256 quote = bridge.getOneInchQuote(address(tokenA), address(axlUSDC), amount);
        
        // Should return amount with 5% slippage (95% of input)
        assertEq(quote, (amount * 95) / 100);
    }
    
    function testUpdateOneInchRouter() public {
        vm.startPrank(owner);
        
        address newRouter = address(0x999);
        bridge.updateOneInchRouter(1, newRouter);
        
        assertEq(bridge.oneInchRouters(1), newRouter);
        
        vm.stopPrank();
    }
    
    function testRevertWhen_UpdateOneInchRouter_NotOwner() public {
        vm.startPrank(user);
        
        address newRouter = address(0x999);
        
        vm.expectRevert();
        bridge.updateOneInchRouter(1, newRouter);
        
        vm.stopPrank();
    }
    
    function testRevertWhen_PayBillWithSwap_UnsupportedChain() public {
        vm.startPrank(user);
        
        uint256 paymentAmount = 100 * 10**6;
        axlUSDC.approve(address(bridge), paymentAmount);
        
        vm.expectRevert();
        // Try to pay to unsupported chain
        bridge.payBillWithSwap{value: 0.01 ether}(
            TEST_BILL_ID,
            address(axlUSDC),
            paymentAmount,
            "axlUSDC",
            "unsupported-chain",
            address(0x123),
            "",
            paymentAmount
        );
        
        vm.stopPrank();
    }
    
    function testRevertWhen_PayBillWithSwap_NoGasFee() public {
        vm.startPrank(user);
        
        uint256 paymentAmount = 100 * 10**6;
        axlUSDC.approve(address(bridge), paymentAmount);
        
        // Mock gateway calls
        vm.mockCall(
            mockGateway,
            abi.encodeWithSignature("tokenAddresses(string)", "axlUSDC"),
            abi.encode(address(axlUSDC))
        );
        
        vm.expectRevert();
        // Try to pay without gas fee - should fail
        bridge.payBillWithSwap(
            TEST_BILL_ID,
            address(axlUSDC),
            paymentAmount,
            "axlUSDC",
            "polygon-mumbai",
            address(0x123),
            "",
            paymentAmount
        );
        
        vm.stopPrank();
    }
    
    function testOneInchRouterInitialization() public {
        // Test that common chain IDs are initialized
        assertEq(bridge.oneInchRouters(1), 0x111111125421cA6dc452d289314280a0f8842A65); // Ethereum
        assertEq(bridge.oneInchRouters(137), 0x111111125421cA6dc452d289314280a0f8842A65); // Polygon
        assertEq(bridge.oneInchRouters(42161), 0x111111125421cA6dc452d289314280a0f8842A65); // Arbitrum
    }
}
