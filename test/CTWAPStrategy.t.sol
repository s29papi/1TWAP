// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {CTWAPStrategy} from "../src/CTWAPStrategy.sol";
import {ILimitOrderProtocol} from "../src/interface/i1inch.sol";
import {iTypes} from "../src/interface/iTypes.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract CTWAPTestBase is Test {
    uint256 private constant _HAS_EXTENSION_FLAG = 1 << 249;
    uint256 private constant _ALLOW_MULTIPLE_FILLS_FLAG = 1 << 254;
    uint256 private constant _PRE_INTERACTION_CALL_FLAG = 1 << 252;
    uint256 private constant _POST_INTERACTION_CALL_FLAG = 1 << 251;
    
    // Base Mainnet Configuration
    uint256 constant BASE_FORK_BLOCK = 24_000_000; // Update with recent block
    string constant BASE_RPC_URL = "https://mainnet.base.org"; // Or use your preferred RPC

    CTWAPStrategy cTWAPStrategy;

    // 1inch Limit Order Protocol is deployed at same address across chains
    ILimitOrderProtocol constant oneLOP = ILimitOrderProtocol(0x111111125421cA6dc452d289314280a0f8842A65);

    uint256 private alicePrvKey = 0xae589c7464eb92dd55ddd629fda5d45c1379cb0522201394dc365f0dd1b07972;
    uint256 private bobPrvKey = 0xb11101fdbb13e868638e208cabbe234c7d980fd21a98f66b89daa186a08fa4f6;
    address private alice;
    address private bob;

    // Base Mainnet tokens
    address constant WETH = 0x4200000000000000000000000000000000000006; // Base WETH
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base USDC (native)
    address constant USDbC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // USDbC (bridged)
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb; // Base DAI
    address constant cbETH = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22; // Coinbase Wrapped Staked ETH

    // Base Mainnet Chainlink oracles
    address constant ETH_USD_ORACLE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant USDC_USD_ORACLE = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address constant cbETH_USD_ORACLE = 0x806b4Ac04501c29769051e42783cF04dCE41440b;
    address constant SEQUENCER_UPTIME_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433; // Base L2 Sequencer

    event CTWAPOrderCreated(bytes32 indexed orderHash, iTypes.CTWAPParams params);
    event TWAPChunkExecuted(bytes32 indexed orderHash, uint256 chunkNumber, uint256 makingAmount, uint256 takingAmount);
    event TWAPOrderCompleted(bytes32 indexed orderHash, uint256 totalMakingAmount, uint256 totalTakingAmount);
    event VolatilityUpdate(bytes32 indexed orderHash, uint256 annualizedVolatility, uint256 price, uint256 timestamp);

    function setUp() public {
        alice = vm.addr(alicePrvKey);
        bob = vm.addr(bobPrvKey);
        vm.createSelectFork(BASE_RPC_URL, BASE_FORK_BLOCK);

        cTWAPStrategy = new CTWAPStrategy();
        cTWAPStrategy.setResolverAuthorization(bob, true);

        // Setup balances for Base tokens
        deal(WETH, alice, 100 ether);
        deal(USDC, bob, 10_000_000 * 1e6);
        deal(cbETH, alice, 50 ether);
        deal(DAI, alice, 100_000 * 1e18);

        // Approve 1inch
        vm.startPrank(alice);
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);
        IERC20(cbETH).approve(address(oneLOP), type(uint256).max);
        IERC20(DAI).approve(address(oneLOP), type(uint256).max);
        vm.stopPrank();

        vm.prank(bob);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);
    }

    // Helper functions remain the same
    function _createCTWAPOrder(
        address makerAsset,
        address takerAsset,
        uint256 totalMaking,
        uint256 totalTaking,
        iTypes.CTWAPParams memory params
    ) internal returns (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) {
        extension = _buildPrePostExtension(address(cTWAPStrategy));
        uint256 extHash160 = uint256(keccak256(extension)) & ((1 << 160) - 1);
        uint256 randHi = uint256(keccak256(abi.encodePacked(block.timestamp, alice, totalMaking))) >> 160;
        uint256 salt = (randHi << 160) | extHash160;

        order = ILimitOrderProtocol.Order({
            salt: salt,
            maker: uint256(uint160(alice)),
            receiver: uint256(uint160(alice)),
            makerAsset: uint256(uint160(makerAsset)),
            takerAsset: uint256(uint160(takerAsset)),
            makingAmount: totalMaking,
            takingAmount: totalTaking,
            makerTraits: _makerTraitsWithExtension()
        });

        (r, vs) = _sign(order, alicePrvKey);
        bytes32 orderHash = oneLOP.hashOrder(order);

        vm.prank(alice);
        cTWAPStrategy.registerCTWAPOrder(orderHash, params);
    }

    function _makerTraitsWithExtension() internal pure returns (uint256) {
        return _HAS_EXTENSION_FLAG | _ALLOW_MULTIPLE_FILLS_FLAG | _PRE_INTERACTION_CALL_FLAG | _POST_INTERACTION_CALL_FLAG;
    }

    function _takerTraitsForExtension(bytes memory extension) internal pure returns (uint256) {
        uint256 fillByMakingFlag = 1 << 255;
        uint256 extensionLenBits = uint256(extension.length) << 224;
        return fillByMakingFlag | extensionLenBits;
    }

    function _sign(ILimitOrderProtocol.Order memory order, uint256 pk) internal view returns (bytes32 r, bytes32 vs) {
        bytes32 orderHash = oneLOP.hashOrder(order);
        (uint8 v, bytes32 rr, bytes32 s) = vm.sign(pk, orderHash);
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

    // Test 1: Basic TWAP on Base with WETH/USDC
    function test_Base_BasicTWAP() public {
        console.log("=== Test 1: Base Basic TWAP Execution ===");

        uint256 totalMaking = 10 ether;
        uint256 totalTaking = 30_000 * 1e6;
        uint256 numChunks = 5;

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) = _createCTWAPOrder(
            WETH,
            USDC,
            totalMaking,
            totalTaking,
            iTypes.CTWAPParams({
                baseParams: iTypes.TWAPParams({
                    initialized: false,
                    totalChunks: numChunks,
                    chunkInterval: 300,
                    startTime: uint64(block.timestamp),
                    endTime: uint64(block.timestamp + 2 hours),
                    minChunkSize: totalMaking / 20,
                    maxPriceImpact: 500
                }),
                volatilityEnabled: false,
                minVolatility: 0,
                maxVolatility: 0,
                volatilityWindow: 0,
                priceOracle: address(0),
                volatilityOracle: address(0),
                sequencerOracle: address(0),
                maxPriceStaleness: 0,
                adaptiveChunkSize: false,
                continuousMode: false,
                makerAsset: WETH
            })
        );

        bytes32 orderHash = oneLOP.hashOrder(order);
        
        // Execute first chunk
        vm.prank(bob);
        (uint256 makingAmount, uint256 takingAmount,) = oneLOP.fillOrderArgs(
            order, r, vs, totalMaking / numChunks, _takerTraitsForExtension(extension), extension
        );

        assertEq(makingAmount, totalMaking / numChunks, "First chunk should execute correctly");
        
        (uint256 executedChunks,,,) = cTWAPStrategy.twapStates(orderHash);
        assertEq(executedChunks, 1, "Should have executed 1 chunk");

        console.log("Base TWAP executes chunks correctly");
    }

    // Test 2: Volatility TWAP with Base ETH oracle
    function test_Base_VolatilityTWAP() public {
        console.log("=== Test 2: Base Volatility TWAP with ETH Oracle ===");

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) = _createCTWAPOrder(
            WETH,
            USDC,
            5 ether,
            15_000 * 1e6,
            iTypes.CTWAPParams({
                baseParams: iTypes.TWAPParams({
                    initialized: false,
                    totalChunks: 3,
                    chunkInterval: 300,
                    startTime: uint64(block.timestamp),
                    endTime: uint64(block.timestamp + 2 hours),
                    minChunkSize: 0.5 ether,
                    maxPriceImpact: 500
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
                makerAsset: WETH
            })
        );

        bytes32 orderHash = oneLOP.hashOrder(order);
        
        // Check volatility is calculated
        uint256 volatility = cTWAPStrategy.getCurrentVolatility(orderHash);
        console.log("Current ETH volatility on Base (bps):", volatility);
        assertGt(volatility, 0, "Volatility should be calculated");

        // Check if can execute based on volatility
        (bool canExecute, string memory reason) = cTWAPStrategy.canExecuteVolatilityChunk(orderHash);
        console.log("Can execute:", canExecute, "Reason:", reason);
        
        console.log("Base volatility calculation works");
    }

    // Test 3: cbETH/USDC TWAP (Base-specific asset)
    function test_Base_cbETH_TWAP() public {
        console.log("=== Test 3: Base cbETH/USDC TWAP ===");

        uint256 totalMaking = 5 ether;
        uint256 totalTaking = 15_000 * 1e6;

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) = _createCTWAPOrder(
            cbETH,
            USDC,
            totalMaking,
            totalTaking,
            iTypes.CTWAPParams({
                baseParams: iTypes.TWAPParams({
                    initialized: false,
                    totalChunks: 4,
                    chunkInterval: 600,
                    startTime: uint64(block.timestamp),
                    endTime: uint64(block.timestamp + 3 hours),
                    minChunkSize: totalMaking / 10,
                    maxPriceImpact: 300
                }),
                volatilityEnabled: true,
                minVolatility: 50,    // Lower vol for staked ETH
                maxVolatility: 10000, // 100% max
                volatilityWindow: 3600,
                priceOracle: cbETH_USD_ORACLE,
                volatilityOracle: address(0),
                sequencerOracle: SEQUENCER_UPTIME_FEED,
                maxPriceStaleness: 3600,
                adaptiveChunkSize: true,
                continuousMode: false,
                makerAsset: cbETH
            })
        );

        bytes32 orderHash = oneLOP.hashOrder(order);
        uint256 chunkSize = totalMaking / 4;

        // Execute first chunk
        vm.prank(bob);
        (uint256 makingAmount,,) = oneLOP.fillOrderArgs(
            order, r, vs, chunkSize, _takerTraitsForExtension(extension), extension
        );

        assertEq(makingAmount, chunkSize, "cbETH chunk should execute");
        console.log("Base-specific cbETH TWAP works correctly");
    }

    // Test 4: DAI/USDC stable-to-stable TWAP
    function test_Base_StableToStable_TWAP() public {
        console.log("=== Test 4: Base DAI/USDC Stable TWAP ===");

        uint256 totalMaking = 10_000 * 1e18; // 10k DAI
        uint256 totalTaking = 10_000 * 1e6;  // 10k USDC

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) = _createCTWAPOrder(
            DAI,
            USDC,
            totalMaking,
            totalTaking,
            iTypes.CTWAPParams({
                baseParams: iTypes.TWAPParams({
                    initialized: false,
                    totalChunks: 10,
                    chunkInterval: 300,
                    startTime: uint64(block.timestamp),
                    endTime: uint64(block.timestamp + 1 hours),
                    minChunkSize: totalMaking / 20,
                    maxPriceImpact: 50 // Tight for stables
                }),
                volatilityEnabled: false, // No vol check for stables
                minVolatility: 0,
                maxVolatility: 0,
                volatilityWindow: 0,
                priceOracle: address(0),
                volatilityOracle: address(0),
                sequencerOracle: address(0),
                maxPriceStaleness: 0,
                adaptiveChunkSize: false,
                continuousMode: true, // Allow rapid execution for stables
                makerAsset: DAI
            })
        );

        // Execute multiple chunks rapidly
        uint256 chunkSize = totalMaking / 10;
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(bob);
            (uint256 makingAmount,,) = oneLOP.fillOrderArgs(
                order, r, vs, chunkSize, _takerTraitsForExtension(extension), extension
            );
            assertEq(makingAmount, chunkSize, "Stable chunk should execute");
            
            if (i < 2) {
                vm.warp(block.timestamp + 61); // Min interval in continuous mode
            }
        }

        console.log("Stable-to-stable TWAP on Base works correctly");
    }

    // Test 5: L2 Sequencer check
    function test_Base_SequencerCheck() public {
        console.log("=== Test 5: Base L2 Sequencer Uptime Check ===");

        // Note: In a real fork, the sequencer should be up
        // This test verifies the integration works
        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) = _createCTWAPOrder(
            WETH,
            USDC,
            2 ether,
            6_000 * 1e6,
            iTypes.CTWAPParams({
                baseParams: iTypes.TWAPParams({
                    initialized: false,
                    totalChunks: 2,
                    chunkInterval: 300,
                    startTime: uint64(block.timestamp),
                    endTime: uint64(block.timestamp + 1 hours),
                    minChunkSize: 0.5 ether,
                    maxPriceImpact: 500
                }),
                volatilityEnabled: true,
                minVolatility: 100,
                maxVolatility: 50000,
                volatilityWindow: 3600,
                priceOracle: ETH_USD_ORACLE,
                volatilityOracle: address(0),
                sequencerOracle: SEQUENCER_UPTIME_FEED, // Base sequencer feed
                maxPriceStaleness: 3600,
                adaptiveChunkSize: false,
                continuousMode: false,
                makerAsset: WETH
            })
        );

        // If sequencer is up, execution should work
        vm.prank(bob);
        (uint256 makingAmount,,) = oneLOP.fillOrderArgs(
            order, r, vs, 1 ether, _takerTraitsForExtension(extension), extension
        );

        assertGt(makingAmount, 0, "Should execute when sequencer is up");
        console.log("Base sequencer check integration verified");
    }

    // Test 6: Small USDC to WETH swap
    function test_Base_SmallUSDCtoWETH() public {
        console.log("=== Test 6: Small USDC to WETH Swap (2 USDC) ===");

        // First, give Alice some USDC
        deal(USDC, alice, 100 * 1e6); // 100 USDC
        vm.prank(alice);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);

        // Give Bob some WETH to take the order
        deal(WETH, bob, 10 ether);
        vm.prank(bob);
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);

        uint256 totalMakingUSDC = 2 * 1e6; // 2 USDC
        // Assuming ETH price ~$3000, 2 USDC should get ~0.000666 ETH
        uint256 totalTakingWETH = 666666666666666; // ~0.000666 ETH

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) = _createCTWAPOrder(
            USDC,
            WETH,
            totalMakingUSDC,
            totalTakingWETH,
            iTypes.CTWAPParams({
                baseParams: iTypes.TWAPParams({
                    initialized: false,
                    totalChunks: 1, // Single chunk for small amount
                    chunkInterval: 300,
                    startTime: uint64(block.timestamp),
                    endTime: uint64(block.timestamp + 1 hours),
                    minChunkSize: totalMakingUSDC / 2, // Allow partial fills down to 1 USDC
                    maxPriceImpact: 1000 // 10% - higher tolerance for small trades
                }),
                volatilityEnabled: true,
                minVolatility: 100,
                maxVolatility: 50000,
                volatilityWindow: 3600,
                priceOracle: ETH_USD_ORACLE, // Using ETH oracle for price reference
                volatilityOracle: address(0),
                sequencerOracle: SEQUENCER_UPTIME_FEED,
                maxPriceStaleness: 3600,
                adaptiveChunkSize: false,
                continuousMode: false,
                makerAsset: USDC
            })
        );

        bytes32 orderHash = oneLOP.hashOrder(order);
        
        // Check initial balances
        uint256 aliceUSDCBefore = IERC20(USDC).balanceOf(alice);
        uint256 aliceWETHBefore = IERC20(WETH).balanceOf(alice);
        uint256 bobUSDCBefore = IERC20(USDC).balanceOf(bob);
        uint256 bobWETHBefore = IERC20(WETH).balanceOf(bob);
        
        console.log("Alice USDC before:", aliceUSDCBefore / 1e6, "USDC");
        console.log("Alice WETH before:", aliceWETHBefore / 1e18, "WETH");
        console.log("Bob USDC before:", bobUSDCBefore / 1e6, "USDC");
        console.log("Bob WETH before:", bobWETHBefore / 1e18, "WETH");

        // Check volatility
        uint256 volatility = cTWAPStrategy.getCurrentVolatility(orderHash);
        console.log("Current ETH volatility (bps):", volatility);

        // Execute the swap
        vm.prank(bob);
        (uint256 makingAmount, uint256 takingAmount,) = oneLOP.fillOrderArgs(
            order, r, vs, totalMakingUSDC, _takerTraitsForExtension(extension), extension
        );

        console.log("Executed - Making (USDC):", makingAmount / 1e6, "Taking (WETH):", takingAmount);

        // Check final balances
        uint256 aliceUSDCAfter = IERC20(USDC).balanceOf(alice);
        uint256 aliceWETHAfter = IERC20(WETH).balanceOf(alice);
        uint256 bobUSDCAfter = IERC20(USDC).balanceOf(bob);
        uint256 bobWETHAfter = IERC20(WETH).balanceOf(bob);

        console.log("Alice USDC after:", aliceUSDCAfter / 1e6, "USDC");
        console.log("Alice WETH after:", aliceWETHAfter / 1e18, "WETH");
        console.log("Bob USDC after:", bobUSDCAfter / 1e6, "USDC");
        console.log("Bob WETH after:", bobWETHAfter / 1e18, "WETH");

        // Assertions
        assertEq(makingAmount, totalMakingUSDC, "Should swap full 2 USDC");
        assertEq(aliceUSDCBefore - aliceUSDCAfter, totalMakingUSDC, "Alice should send 2 USDC");
        assertEq(aliceWETHAfter - aliceWETHBefore, takingAmount, "Alice should receive WETH");
        assertEq(bobUSDCAfter - bobUSDCBefore, makingAmount, "Bob should receive 2 USDC");
        assertEq(bobWETHBefore - bobWETHAfter, takingAmount, "Bob should send WETH");

        console.log("Small USDC to WETH swap executed successfully");
        // console.log("Swapped", makingAmount / 1e6, "USDC for", takingAmount, "wei (", takingAmount / 1e15, "finney)");
    }
}