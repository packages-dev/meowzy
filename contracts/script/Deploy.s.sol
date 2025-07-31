// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MerkleVerifier.sol";
import "../src/PaymentManager.sol";
import "../src/CrossChainBridge.sol";
import "../src/CrossChainBillSplitter.sol";

contract DeployScript is Script {
    function run() external {
        // Use the private key from command line or environment variable
        uint256 deployerPrivateKey;
        try vm.envUint("PRIVATE_KEY") returns (uint256 envKey) {
            deployerPrivateKey = envKey;
        } catch {
            // If PRIVATE_KEY env var not found, use the default anvil test key
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }
        
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying contracts with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MerkleVerifier
        MerkleVerifier merkleVerifier = new MerkleVerifier();
        console.log("MerkleVerifier deployed at:", address(merkleVerifier));
        
        // Deploy PaymentManager
        PaymentManager paymentManager = new PaymentManager(
            address(merkleVerifier),
            deployer // Fee recipient
        );
        console.log("PaymentManager deployed at:", address(paymentManager));
        
        // Deploy CrossChainBridge
        // Note: You'll need to set actual Axelar gateway and gas service addresses for each network
        address axelarGateway = getAxelarGateway();
        address axelarGasService = getAxelarGasService();
        
        CrossChainBridge crossChainBridge = new CrossChainBridge(
            axelarGateway,
            axelarGasService
        );
        console.log("CrossChainBridge deployed at:", address(crossChainBridge));
        
        // Deploy main CrossChainBillSplitter
        CrossChainBillSplitter billSplitter = new CrossChainBillSplitter(
            address(merkleVerifier),
            address(paymentManager),
            address(crossChainBridge)
        );
        console.log("CrossChainBillSplitter deployed at:", address(billSplitter));
        
        // Add some supported tokens to PaymentManager
        // Add USDC (you'll need actual token addresses for each network)
        address usdcToken = getUSDCAddress();
        if (usdcToken != address(0)) {
            paymentManager.addSupportedToken(usdcToken);
            console.log("Added USDC token support:", usdcToken);
        }
        
        vm.stopBroadcast();
        
        // Log deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network:", getChainName());
        console.log("Deployer:", deployer);
        console.log("MerkleVerifier:", address(merkleVerifier));
        console.log("PaymentManager:", address(paymentManager));
        console.log("CrossChainBridge:", address(crossChainBridge));
        console.log("CrossChainBillSplitter:", address(billSplitter));
        console.log("==========================\n");
        
        // Save deployment addresses to file
        string memory deploymentInfo = string(abi.encodePacked(
            "{\n",
            '  "network": "', getChainName(), '",\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "contracts": {\n',
            '    "MerkleVerifier": "', vm.toString(address(merkleVerifier)), '",\n',
            '    "PaymentManager": "', vm.toString(address(paymentManager)), '",\n',
            '    "CrossChainBridge": "', vm.toString(address(crossChainBridge)), '",\n',
            '    "CrossChainBillSplitter": "', vm.toString(address(billSplitter)), '"\n',
            '  }\n',
            '}'
        ));
        
        string memory fileName = string(abi.encodePacked("deployments/", getChainName(), ".json"));
        vm.writeFile(fileName, deploymentInfo);
        console.log("Deployment info saved to:", fileName);
    }
    
    function getAxelarGateway() internal view returns (address) {
        uint256 chainId = block.chainid;
        
        // Sepolia
        if (chainId == 11155111) {
            return 0xe432150cce91c13a887f7D836923d5597adD8E31;
        }
        // Polygon Mumbai
        else if (chainId == 80001) {
            return 0xBF62ef1486468a6bd26Dd669C06db43dEd5B849B;
        }
        // Arbitrum Goerli
        else if (chainId == 421613) {
            return 0xe432150cce91c13a887f7D836923d5597adD8E31;
        }
        // Default fallback (update with actual addresses)
        else {
            console.log("Warning: Unknown chain ID, using default gateway address");
            return 0xe432150cce91c13a887f7D836923d5597adD8E31;
        }
    }
    
    function getAxelarGasService() internal view returns (address) {
        uint256 chainId = block.chainid;
        
        // Sepolia
        if (chainId == 11155111) {
            return 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6;
        }
        // Polygon Mumbai
        else if (chainId == 80001) {
            return 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6;
        }
        // Arbitrum Goerli
        else if (chainId == 421613) {
            return 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6;
        }
        // Default fallback
        else {
            console.log("Warning: Unknown chain ID, using default gas service address");
            return 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6;
        }
    }
    
    function getUSDCAddress() internal view returns (address) {
        uint256 chainId = block.chainid;
        
        // Sepolia (aUSDC from Axelar)
        if (chainId == 11155111) {
            return 0x254d06f33bDc5b8ee05b2ea472107E300226659A;
        }
        // Polygon Mumbai (aUSDC from Axelar)
        else if (chainId == 80001) {
            return 0x2c852e740B62308c46DD29B982FBb650D063Bd07;
        }
        // Arbitrum Goerli (aUSDC from Axelar)
        else if (chainId == 421613) {
            return 0xfd064A18f3BF249cf1f87FC203E90D8f650f2d63;
        }
        else {
            return address(0);
        }
    }
    
    function getChainName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        
        if (chainId == 1) return "mainnet";
        else if (chainId == 11155111) return "sepolia";
        else if (chainId == 137) return "polygon";
        else if (chainId == 80001) return "mumbai";
        else if (chainId == 42161) return "arbitrum";
        else if (chainId == 421613) return "arbitrum-goerli";
        else if (chainId == 31337) return "Anvil";
        else if (chainId == 202102) return "thane";
        else return "unknown";
    }
}
