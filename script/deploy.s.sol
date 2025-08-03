// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {CTWAPStrategy} from "../src/CTWAPStrategy.sol";
import {ILimitOrderProtocol} from "../src/interface/i1inch.sol";
import {iTypes} from "../src/interface/iTypes.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

// Script 1: Create and register the order
contract CreateCTWAPOrder is Script {
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

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address strategyAddress = vm.envAddress("CTWAP_STRATEGY");
        address maker = vm.addr(privateKey);
        
        CTWAPStrategy cTWAPStrategy = CTWAPStrategy(strategyAddress);
        
        // Order parameters
  uint256 totalMakingAmount = 1 * 1e6; // 1 USDC (6 decimals)
        uint256 totalTakingAmount = 286388824373576;
        uint256 totalChunks = vm.envOr("TOTAL_CHUNKS", uint256(2));
        uint256 chunkInterval = vm.envOr("CHUNK_INTERVAL", uint256(20)); // 30 seconds default
        
        // Build order
        bytes memory extension = _buildPrePostExtension(strategyAddress);
        uint256 extHash160 = uint256(keccak256(extension)) & ((1 << 160) - 1);
        uint256 salt = (block.timestamp << 160) | extHash160;
        
        ILimitOrderProtocol.Order memory order = ILimitOrderProtocol.Order({
            salt: salt,
            maker: uint256(uint160(maker)),
            receiver: uint256(uint160(maker)),
            makerAsset: uint256(uint160(USDC)),
            takerAsset: uint256(uint160(WETH)),
            makingAmount: totalMakingAmount,
            takingAmount: totalTakingAmount,
            makerTraits: _makerTraitsWithExtension()
        });
        
        // Sign order
        bytes32 orderHash = oneLOP.hashOrder(order);
        (bytes32 r, bytes32 vs) = _signOrder(orderHash, privateKey);
        
        // Register CTWAP parameters
          // Register CTWAP parameters
        iTypes.CTWAPParams memory params = iTypes.CTWAPParams({
            baseParams: iTypes.TWAPParams({
                initialized: false,
                totalChunks: totalChunks,
                chunkInterval: chunkInterval,
                startTime: uint64(block.timestamp),
                endTime: uint64(block.timestamp + (totalChunks * chunkInterval) + 200), // Add 5 min buffer
                minChunkSize: totalMakingAmount / (totalChunks * 2),
                maxPriceImpact: 2000
            }),
            volatilityEnabled: true,
            minVolatility: 100,
            maxVolatility: 50000,
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
        
        // Approve tokens
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);
        
        // // Get WETH for filling
        // uint256 wethNeeded = totalTakingAmount + 0.001 ether;
        // (bool success,) = WETH.call{value: wethNeeded}("");
        // require(success, "WETH wrap failed");
        // IERC20(WETH).approve(address(oneLOP), type(uint256).max);
        
        // Register order
        cTWAPStrategy.registerCTWAPOrder(orderHash, params);
        
        vm.stopBroadcast();
        
        // Output order details for shell script
        console.log("ORDER_CREATED=true");
        console.log("ORDER_HASH=", vm.toString(orderHash));
        console.log("ORDER_SALT=", salt);
        console.log("ORDER_R=", vm.toString(r));
        console.log("ORDER_VS=", vm.toString(vs));
        console.log("MAKER_ADDRESS=", maker);
        console.log("MAKING_AMOUNT=", totalMakingAmount);
        console.log("TAKING_AMOUNT=", totalTakingAmount);
        console.log("TOTAL_CHUNKS=", totalChunks);
        console.log("CHUNK_INTERVAL=", chunkInterval);
        console.log("EXTENSION_LENGTH=", extension.length);
    }
    
    function _makerTraitsWithExtension() internal pure returns (uint256) {
        return _HAS_EXTENSION_FLAG | _ALLOW_MULTIPLE_FILLS_FLAG | _PRE_INTERACTION_CALL_FLAG | _POST_INTERACTION_CALL_FLAG;
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
        
        for (uint256 i = 0; i < 6; i++) {
            offsets[i] = offset;
        }
        
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

// Script 2: Execute a chunk of the order
contract ExecuteCTWAPChunk is Script {
    ILimitOrderProtocol constant oneLOP = ILimitOrderProtocol(0x111111125421cA6dc452d289314280a0f8842A65);
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    uint256 private constant _HAS_EXTENSION_FLAG = 1 << 249;
    uint256 private constant _ALLOW_MULTIPLE_FILLS_FLAG = 1 << 254;
    uint256 private constant _PRE_INTERACTION_CALL_FLAG = 1 << 252;
    uint256 private constant _POST_INTERACTION_CALL_FLAG = 1 << 251;
    
    function run() public {
        // Read order details from environment
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address strategyAddress = vm.envAddress("CTWAP_STRATEGY");
        
        // Order parameters from env
        bytes32 orderHash = vm.envBytes32("ORDER_HASH");
        uint256 salt = vm.envUint("ORDER_SALT");
        bytes32 r = vm.envBytes32("ORDER_R");
        bytes32 vs = vm.envBytes32("ORDER_VS");
        address maker = vm.envAddress("MAKER_ADDRESS");
        uint256 makingAmount = vm.envUint("MAKING_AMOUNT");
        uint256 takingAmount = vm.envUint("TAKING_AMOUNT");
        uint256 totalChunks = vm.envUint("TOTAL_CHUNKS");
        uint256 chunkNumber = vm.envOr("CHUNK_NUMBER", uint256(1));
        
        CTWAPStrategy cTWAPStrategy = CTWAPStrategy(strategyAddress);
        
        console.log("\n=== Executing Chunk %d of %d ====", chunkNumber, totalChunks);
        
        // Check if can execute
        (bool canExecute, string memory reason) = cTWAPStrategy.canExecuteVolatilityChunk(orderHash);
        console.log("Can execute:", canExecute);
        
        if (!canExecute) {
            console.log("Cannot execute chunk. Reason:", reason);
            console.log("CHUNK_EXECUTED=false");
            return;
        }
        
        // Rebuild order
        bytes memory extension = _buildPrePostExtension(strategyAddress);
        
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
        
        // Calculate chunk size
        uint256 chunkMakingAmount = makingAmount / totalChunks;
        
        // Log balances before
        console.log("Before chunk:");
        console.log("  USDC:", IERC20(USDC).balanceOf(maker) / 1e6, "USDC");
        console.log("  WETH:", IERC20(WETH).balanceOf(maker) / 1e15, "finney");
        
        vm.startBroadcast(privateKey);
        
        // Fill the chunk
        uint256 takerTraits = _takerTraitsForExtension(extension);
        
        try oneLOP.fillOrderArgs(order, r, vs, chunkMakingAmount, takerTraits, extension) 
        returns (uint256 actualMaking, uint256 actualTaking, bytes32) {
            console.log("\nChunk filled successfully!");
            console.log("  Making amount:", actualMaking / 1e6, "USDC");
            console.log("  Taking amount:", actualTaking / 1e15, "finney");
            console.log("CHUNK_EXECUTED=true");
            
        } catch Error(string memory err) {
            console.log("Fill failed:", err);
            console.log("CHUNK_EXECUTED=false");
        } catch (bytes memory err) {
            console.log("Fill failed with bytes:", vm.toString(err));
            console.log("CHUNK_EXECUTED=false");
        }
        
        vm.stopBroadcast();
        
        // Log balances after
        console.log("\nAfter chunk:");
        console.log("  USDC:", IERC20(USDC).balanceOf(maker) / 1e6, "USDC");
        console.log("  WETH:", IERC20(WETH).balanceOf(maker) / 1e15, "finney");
    }
    
    function _makerTraitsWithExtension() internal pure returns (uint256) {
        return _HAS_EXTENSION_FLAG | _ALLOW_MULTIPLE_FILLS_FLAG | _PRE_INTERACTION_CALL_FLAG | _POST_INTERACTION_CALL_FLAG;
    }
    
    function _takerTraitsForExtension(bytes memory extension) internal pure returns (uint256) {
        uint256 fillByMakingFlag = 1 << 255;
        uint256 extensionLenBits = uint256(extension.length) << 224;
        return fillByMakingFlag | extensionLenBits;
    }
    
    function _buildPrePostExtension(address strategy) internal pure returns (bytes memory ext) {
        bytes memory pre = abi.encodePacked(strategy);
        bytes memory post = abi.encodePacked(strategy);
        
        uint256 offset = 0;
        uint256[] memory offsets = new uint256[](8);
        
        for (uint256 i = 0; i < 6; i++) {
            offsets[i] = offset;
        }
        
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