// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {CTWAPStrategy} from "../src/CTWAPStrategy.sol";
import {ILimitOrderProtocol} from "../src/interface/i1inch.sol";
import {iTypes} from "../src/interface/iTypes.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract DeployAndTestCTWAP is Script {
    // Constants
    uint256 private constant _HAS_EXTENSION_FLAG = 1 << 249;
    uint256 private constant _ALLOW_MULTIPLE_FILLS_FLAG = 1 << 254;
    uint256 private constant _PRE_INTERACTION_CALL_FLAG = 1 << 252;
    uint256 private constant _POST_INTERACTION_CALL_FLAG = 1 << 251;

    // Base Mainnet addresses
    ILimitOrderProtocol constant oneLOP = ILimitOrderProtocol(0x111111125421cA6dc452d289314280a0f8842A65);
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant ETH_USD_ORACLE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant SEQUENCER_UPTIME_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    CTWAPStrategy cTWAPStrategy;

    function run() public {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");
        
        // Check USDC balance
        uint256 usdcBalance = IERC20(USDC).balanceOf(deployer);
        console.log("Deployer USDC balance:", usdcBalance / 1e6, "USDC");
        
        require(usdcBalance >= 2 * 1e6, "Need at least 2 USDC");
        // require(deployer.balance >= 0.01 ether, "Need at least 0.01 ETH for gas");

        // Deploy CTWAP Strategy
        vm.startBroadcast(deployerPrivateKey);
        
        cTWAPStrategy = new CTWAPStrategy();
        console.log("CTWAP Strategy deployed at:", address(cTWAPStrategy));
        
        // Set deployer as authorized resolver
        cTWAPStrategy.setResolverAuthorization(deployer, true);
        console.log("Set deployer as authorized resolver");
        
        // Approve USDC for 1inch
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);
        console.log("Approved USDC for 1inch protocol");
        
        vm.stopBroadcast();

        // Create and execute CTWAP order
        console.log("\n=== Creating CTWAP Order ===");
        _createAndExecuteOrder(deployerPrivateKey);
    }

    function _createAndExecuteOrder(uint256 privateKey) internal {
        address maker = vm.addr(privateKey);
        
        // Order parameters
        uint256 makingAmount = 2 * 1e6; // 2 USDC
        uint256 takingAmount = 582392541595494; // ~0.000666 ETH at $3000/ETH
        
        // Build extension
        bytes memory extension = _buildPrePostExtension(address(cTWAPStrategy));
        uint256 extHash160 = uint256(keccak256(extension)) & ((1 << 160) - 1);
        uint256 salt = (block.timestamp << 160) | extHash160;
        
        // Create order
        ILimitOrderProtocol.Order memory order = ILimitOrderProtocol.Order({
            salt: salt,
            maker: uint256(uint160(maker)),
            receiver: uint256(uint160(maker)),
            makerAsset: uint256(uint160(USDC)),
            takerAsset: uint256(uint160(WETH)),
            makingAmount: makingAmount,
            takingAmount: takingAmount,
            makerTraits: _makerTraitsWithExtension()
        });
        
        // Sign order
        bytes32 orderHash = oneLOP.hashOrder(order);
        (bytes32 r, bytes32 vs) = _signOrder(orderHash, privateKey);
        
        console.log("Order hash:", vm.toString(orderHash));
        
        // Register CTWAP parameters
        iTypes.CTWAPParams memory params = iTypes.CTWAPParams({
            baseParams: iTypes.TWAPParams({
                initialized: false,
                totalChunks: 1,
                chunkInterval: 300,
                startTime: uint64(block.timestamp),
                endTime: uint64(block.timestamp + 1 hours),
                minChunkSize: makingAmount / 2,
                maxPriceImpact: 2000 // 20% tolerance for small trade
            }),
            volatilityEnabled: true,
            minVolatility: 100,    // 1% min
            maxVolatility: 50000,  // 500% max (very wide range)
            volatilityWindow: 3600,
            priceOracle: ETH_USD_ORACLE,
            volatilityOracle: address(0),
            sequencerOracle: SEQUENCER_UPTIME_FEED,
            maxPriceStaleness: 3600,
            adaptiveChunkSize: false,
            continuousMode: false,
            makerAsset: USDC
        });
        
        vm.startBroadcast(privateKey);
        
        // Register the order
        cTWAPStrategy.registerCTWAPOrder(orderHash, params);
        console.log("CTWAP order registered");
        
        // Check current volatility
        uint256 currentVol = cTWAPStrategy.getCurrentVolatility(orderHash);
        console.log("Current ETH volatility: %d bps ( %d %", currentVol,  (currentVol / 100));
        
        // Check if can execute
        (bool canExecute, string memory reason) = cTWAPStrategy.canExecuteVolatilityChunk(orderHash);
        console.log("Can execute:", canExecute);
        if (!canExecute) {
            console.log("Reason:", reason);
            vm.stopBroadcast();
            return;
        }
        
        // For this test, we'll be both maker and taker
        // In production, another address would fill this order
        console.log("\n=== Attempting to fill order ===");
        
        // First, get some WETH to fill the order
        // Wrap some ETH
        uint256 wethNeeded = takingAmount + 0.001 ether; // Extra for safety
        (bool success,) = WETH.call{value: wethNeeded}("");
        require(success, "WETH wrap failed");
        
        // Approve WETH for 1inch
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);
        
        // Log balances before
        console.log("Before fill:");
        console.log("  USDC:", IERC20(USDC).balanceOf(maker) / 1e6, "USDC");
        console.log("  WETH:", IERC20(WETH).balanceOf(maker) / 1e15, "finney");
        
        // Fill the order
        uint256 takerTraits = _takerTraitsForExtension(extension);
        
        try oneLOP.fillOrderArgs(order, r, vs, makingAmount, takerTraits, extension) 
        returns (uint256 actualMaking, uint256 actualTaking, bytes32 filledHash) {
            console.log("\nOrder filled successfully!");
            console.log("  Making amount:", actualMaking / 1e6, "USDC");
            console.log("  Taking amount: %d wei ( %d finney)", actualTaking, actualTaking / 1e15);
            console.log("  Order hash:", vm.toString(filledHash));
            
            // Log final balances
            console.log("\nAfter fill:");
            console.log("  USDC:", IERC20(USDC).balanceOf(maker) / 1e6, "USDC");
            console.log("  WETH:", IERC20(WETH).balanceOf(maker) / 1e15, "finney");
            
        } catch Error(string memory err) {
            console.log("Fill failed:", err);
        } catch (bytes memory err) {
            console.log("Fill failed with bytes:", vm.toString(err));
        }
        
        vm.stopBroadcast();
    }

    // Helper functions
    function _makerTraitsWithExtension() internal pure returns (uint256) {
        return _HAS_EXTENSION_FLAG | _ALLOW_MULTIPLE_FILLS_FLAG | _PRE_INTERACTION_CALL_FLAG | _POST_INTERACTION_CALL_FLAG;
    }

    function _takerTraitsForExtension(bytes memory extension) internal pure returns (uint256) {
        uint256 fillByMakingFlag = 1 << 255;
        uint256 extensionLenBits = uint256(extension.length) << 224;
        return fillByMakingFlag | extensionLenBits;
    }

    function _signOrder(bytes32 orderHash, uint256 privateKey) internal pure returns (bytes32 r, bytes32 vs) {
        (uint8 v, bytes32 rr, bytes32 s) = vm.sign(privateKey, orderHash);
        vs = bytes32((uint256(v - 27) << 255) | uint256(s));
        r = rr;
    }

    function _buildPrePostExtension(address strategy) internal pure returns (bytes memory ext) {
        bytes memory pre = abi.encodePacked(strategy);
        bytes memory post = abi.encodePacked(strategy);

        uint256 offset = 0;
        uint256[] memory offsets = new uint256[](8);

        offsets[0] = offset;
        offsets[1] = offset;
        offsets[2] = offset;
        offsets[3] = offset;
        offsets[4] = offset;
        offsets[5] = offset;

        offset += pre.length;
        offsets[6] = offset;

        offset += post.length;
        offsets[7] = offset;

        uint256 packed = 0;
        for (uint256 i = 0; i < 8; i++) {
            packed |= offsets[i] << (32 * i);
        }

        ext = abi.encodePacked(bytes32(packed), pre, post);
    }
}

// Separate script to just check if an order can be executed
contract CheckCTWAPOrder is Script {
    CTWAPStrategy cTWAPStrategy;
    
    function run() public {
        address strategyAddress = vm.envAddress("CTWAP_STRATEGY");
        bytes32 orderHash = vm.envBytes32("ORDER_HASH");
        
        cTWAPStrategy = CTWAPStrategy(strategyAddress);
        
        console.log("Checking order:", vm.toString(orderHash));
        console.log("Strategy:", strategyAddress);
        
        // Get current volatility
        uint256 vol = cTWAPStrategy.getCurrentVolatility(orderHash);
        console.log("Current volatility: %d bps ( %d % )", vol, (vol / 100));
        
        // Check execution
        (bool canExecute, string memory reason) = cTWAPStrategy.canExecuteVolatilityChunk(orderHash);
        console.log("Can execute:", canExecute);
        if (!canExecute) {
            console.log("Reason:", reason);
        }
        
        // Get TWAP state
        (uint256 executed, uint256 lastTime, uint256 totalMaking, uint256 totalTaking) = 
            cTWAPStrategy.twapStates(orderHash);
        console.log("\nTWAP State:");
        console.log("  Executed chunks:", executed);
        console.log("  Last execution:", lastTime);
        console.log("  Total making:", totalMaking);
        console.log("  Total taking:", totalTaking);
    }
}