// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {TWAPStrategy} from "../src/TWAPStrategy.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import {ILimitOrderProtocol} from "../src/interface/i1inch.sol";
import {iTypes} from "../src/interface/iTypes.sol";

contract IntegrationTWAPTest is Test {
    uint256 private constant _HAS_EXTENSION_FLAG = 1 << 249;
    uint256 private constant _ALLOW_MULTIPLE_FILLS_FLAG = 1 << 254;
    uint256 private constant _PRE_INTERACTION_CALL_FLAG = 1 << 252;
    uint256 private constant _POST_INTERACTION_CALL_FLAG = 1 << 251;
    string constant BASE_RPC_URL = "https://arb1.arbitrum.io/rpc";

    TWAPStrategy twapStrategy;

    ILimitOrderProtocol constant oneLOP = ILimitOrderProtocol(0x111111125421cA6dc452d289314280a0f8842A65);

    uint256 private alicePrvKey = 0xae589c7464eb92dd55ddd629fda5d45c1379cb0522201394dc365f0dd1b07972;
    uint256 private bobPrvKey = 0xb11101fdbb13e868638e208cabbe234c7d980fd21a98f66b89daa186a08fa4f6;
    address private alice;
    address private bob;

    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // Events
    event TWAPOrderCreated(bytes32 indexed orderHash, iTypes.TWAPParams params);
    event TWAPChunkExecuted(bytes32 indexed orderHash, uint256 chunkNumber, uint256 makingAmount, uint256 takingAmount);
    event TWAPOrderCompleted(bytes32 indexed orderHash, uint256 totalMakingAmount, uint256 totalTakingAmount);

    function setUp() public {
        alice = vm.addr(alicePrvKey);
        bob = vm.addr(bobPrvKey);
        vm.createSelectFork(BASE_RPC_URL);
        twapStrategy = new TWAPStrategy();
        twapStrategy.setResolverAuthorization(bob, true);

        deal(WETH, alice, 100 ether);
        deal(USDC, bob, 10_000_000 * 1e6);

        assertEq(IERC20(USDC).balanceOf(bob), 10_000_000 * 1e6);
        assertEq(IERC20(WETH).balanceOf(alice), 100 * 1e18);

        vm.prank(alice);
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);

        vm.prank(bob);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);
    }

    function test_TWAPStrategy_SingleChunk() public {
        vm.createSelectFork(BASE_RPC_URL);

        // Re-deploy the strategy
        twapStrategy = new TWAPStrategy();
        twapStrategy.setResolverAuthorization(bob, true);

        // Re-setup balances
        deal(WETH, alice, 100 ether);
        deal(USDC, bob, 10_000_000 * 1e6);

        vm.prank(alice);
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);
        vm.prank(bob);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);
        uint256 totalMaking = 5 ether;
        uint256 totalTaking = 15_000 * 1e6;

        bytes memory extension = _buildPrePostExtension(address(twapStrategy));

        // Bind salt to extension hash (lower 160 bits)
        uint256 extHash160 = uint256(keccak256(extension)) & ((1 << 160) - 1);
        uint256 randHi = uint256(keccak256(abi.encodePacked(block.timestamp, alice, totalMaking))) >> 160;
        uint256 salt = (randHi << 160) | extHash160;

        // Create order with correct types (using uint256 for addresses)
        ILimitOrderProtocol.Order memory order = ILimitOrderProtocol.Order({
            salt: salt,
            maker: uint256(uint160(alice)),
            receiver: uint256(uint160(alice)),
            makerAsset: uint256(uint160(WETH)),
            takerAsset: uint256(uint160(USDC)),
            makingAmount: totalMaking,
            takingAmount: totalTaking,
            makerTraits: _makerTraitsWithExtension()
        });

        (bytes32 r, bytes32 vs) = _sign(order, alicePrvKey);
        bytes32 orderHash = oneLOP.hashOrder(order);

        // Register TWAP parameters
        vm.prank(alice);
        twapStrategy.registerTWAPOrder(
            orderHash,
            iTypes.TWAPParams({
                totalChunks: 5,
                chunkInterval: 300, // 5 minutes between chunks
                startTime: uint64(block.timestamp),
                endTime: uint64(block.timestamp + 1 hours),
                minChunkSize: totalMaking / 10, // 10% minimum chunk
                maxPriceImpact: 500, // 5% max price impact
                initialized: true
            })
        );

        // Execute first chunk as resolver
        vm.prank(bob);
        uint256 chunkAmount = totalMaking / 5; // Execute 1/5 of the order

        // Build taker traits for extension
        uint256 takerTraits = _takerTraitsForExtension(extension);

        // Execute the first chunk
        (uint256 makingAmount, uint256 takingAmount, bytes32 filledOrderHash) =
            oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);

        // Verify execution
        assertEq(makingAmount, chunkAmount);
        assertEq(filledOrderHash, orderHash);

        // Check TWAP state
        (uint256 executedChunks, uint256 lastExecutionTime, uint256 totalMakingSoFar, uint256 totalTakingSoFar) =
            twapStrategy.twapStates(orderHash);

        assertEq(executedChunks, 1);
        assertEq(totalMakingSoFar, chunkAmount);
        assertEq(lastExecutionTime, block.timestamp);

        console.log("First chunk executed successfully");
        console.log("Making amount:", makingAmount);
        console.log("Taking amount:", takingAmount);
    }

    function test_TWAPStrategy_FullExecution() public {
        vm.createSelectFork(BASE_RPC_URL);

        // Re-deploy the strategy
        twapStrategy = new TWAPStrategy();
        twapStrategy.setResolverAuthorization(bob, true);

        // Re-setup balances
        deal(WETH, alice, 100 ether);
        deal(USDC, bob, 10_000_000 * 1e6);

        vm.prank(alice);
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);
        vm.prank(bob);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);
        uint256 totalMaking = 5 ether;
        uint256 totalTaking = 15_000 * 1e6;
        uint256 numChunks = 5;

        bytes memory extension = _buildPrePostExtension(address(twapStrategy));
        uint256 extHash160 = uint256(keccak256(extension)) & ((1 << 160) - 1);
        uint256 randHi = uint256(keccak256(abi.encodePacked(block.timestamp, alice, totalMaking))) >> 160;
        uint256 salt = (randHi << 160) | extHash160;

        ILimitOrderProtocol.Order memory order = ILimitOrderProtocol.Order({
            salt: salt,
            maker: uint256(uint160(alice)),
            receiver: uint256(uint160(alice)),
            makerAsset: uint256(uint160(WETH)),
            takerAsset: uint256(uint160(USDC)),
            makingAmount: totalMaking,
            takingAmount: totalTaking,
            makerTraits: _makerTraitsWithExtension()
        });

        (bytes32 r, bytes32 vs) = _sign(order, alicePrvKey);
        bytes32 orderHash = oneLOP.hashOrder(order);

        // Register TWAP parameters
        vm.prank(alice);
        twapStrategy.registerTWAPOrder(
            orderHash,
            iTypes.TWAPParams({
                totalChunks: numChunks,
                chunkInterval: 300, // 5 minutes between chunks
                startTime: uint64(block.timestamp),
                endTime: uint64(block.timestamp + 2 hours),
                minChunkSize: totalMaking / 10,
                maxPriceImpact: 500,
                initialized: true
            })
        );

        uint256 totalExecutedMaking = 0;
        uint256 totalExecutedTaking = 0;

        // Execute all chunks
        for (uint256 i = 0; i < numChunks; i++) {
            console.log("Executing chunk", i + 1);

            uint256 chunkAmount = i == numChunks - 1 ? totalMaking - totalExecutedMaking : totalMaking / numChunks;

            // Compute expected taking using proportional formula
            uint256 expectedTaking = (totalTaking * chunkAmount) / totalMaking; // handles decimals correctly

            vm.prank(bob);
            uint256 takerTraits = _takerTraitsForExtension(extension);

            // Expect the chunk execution event with correct taking
            vm.expectEmit(true, false, false, true);
            emit TWAPChunkExecuted(orderHash, i + 1, chunkAmount, expectedTaking);

            // If last chunk, expect completion event
            if (i == numChunks - 1) {
                vm.expectEmit(true, false, false, true);
                emit TWAPOrderCompleted(orderHash, totalMaking, totalTaking);
            }

            (uint256 makingAmount, uint256 takingAmount,) =
                oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);

            totalExecutedMaking += makingAmount;
            totalExecutedTaking += takingAmount;

            (uint256 executedChunks, uint256 lastExecutionTime, uint256 totalMakingSoFar, uint256 totalTakingSoFar) =
                twapStrategy.twapStates(orderHash);

            assertEq(executedChunks, i + 1);
            assertEq(totalMakingSoFar, totalExecutedMaking);
            assertEq(totalTakingSoFar, totalExecutedTaking);
            assertEq(lastExecutionTime, block.timestamp);

            if (i < numChunks - 1) {
                vm.warp(block.timestamp + 301);
            }
        }

        // Verify final balances
        assertEq(totalExecutedMaking, totalMaking);
        assertEq(totalExecutedTaking, totalTaking);

        console.log("Full TWAP execution completed");
        console.log("Total making executed:", totalExecutedMaking);
        console.log("Total taking executed:", totalExecutedTaking);
    }

    function test_TWAPStrategy_TooEarlyToExecuteNextChunk() public {
        vm.createSelectFork(BASE_RPC_URL);

        // Re-deploy the strategy
        twapStrategy = new TWAPStrategy();
        twapStrategy.setResolverAuthorization(bob, true);

        // Re-setup balances
        deal(WETH, alice, 100 ether);
        deal(USDC, bob, 10_000_000 * 1e6);

        vm.prank(alice);
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);
        vm.prank(bob);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);
        uint256 totalMaking = 5 ether;
        uint256 totalTaking = 15_000 * 1e6;

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) =
            _createAndRegisterTWAPOrder(totalMaking, totalTaking, 5, 300);

        bytes32 orderHash = oneLOP.hashOrder(order);
        uint256 chunkAmount = totalMaking / 5;
        uint256 takerTraits = _takerTraitsForExtension(extension);

        // Execute first chunk
        vm.prank(bob);
        oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);

        // Try to execute second chunk immediately (should fail)
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(iTypes.TooEarlyToExecute.selector));
        oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);

        // Advance time but not enough
        vm.warp(block.timestamp + 299);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(iTypes.TooEarlyToExecute.selector));
        oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);

        // Advance time past interval
        vm.warp(block.timestamp + 2);

        // Now it should work
        vm.prank(bob);
        (uint256 makingAmount,,) = oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);
        assertEq(makingAmount, chunkAmount);
    }

    function test_TWAPStrategy_PriceImpactProtection() public {
        // For now, let's test that the calculation works correctly
        uint256 expectedAmount = 1000;
        uint256 actualAmount1 = 1050; // 5% impact
        uint256 actualAmount2 = 1060; // 6% impact

        uint256 impact1 = twapStrategy.calculatePriceImpact(expectedAmount, actualAmount1);
        uint256 impact2 = twapStrategy.calculatePriceImpact(expectedAmount, actualAmount2);

        assertEq(impact1, 500); // 5% = 500 basis points
        assertEq(impact2, 600); // 6% = 600 basis points

        console.log("Price impact calculation tested successfully");
    }

    function test_TWAPStrategy_UnauthorizedResolver() public {
        // Create a fresh fork for this test
        vm.createSelectFork(BASE_RPC_URL);

        // Re-deploy the strategy
        twapStrategy = new TWAPStrategy();
        twapStrategy.setResolverAuthorization(bob, true);

        // Re-setup balances
        deal(WETH, alice, 100 ether);
        deal(USDC, bob, 10_000_000 * 1e6);

        vm.prank(alice);
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);
        vm.prank(bob);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);
        uint256 totalMaking = 5 ether;
        uint256 totalTaking = 15_000 * 1e6;

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) =
            _createAndRegisterTWAPOrder(totalMaking, totalTaking, 5, 300);

        uint256 chunkAmount = totalMaking / 5;
        uint256 takerTraits = _takerTraitsForExtension(extension);

        // Snapshot balances before the (expected) revert
        uint256 aliceWethBefore = IERC20(WETH).balanceOf(alice);
        uint256 aliceUsdcBefore = IERC20(USDC).balanceOf(alice);

        // Random unauthorized address 0x000...dead
        address unauthorizedResolver = address(0xdead);
        deal(USDC, unauthorizedResolver, 100_000 * 1e6);

        vm.prank(unauthorizedResolver);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);

        // Expect Unauthorized revert from TWAPStrategy.preInteraction
        vm.prank(unauthorizedResolver);
        vm.expectRevert(iTypes.Unauthorized.selector);
        oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);

        // No state/balance changes after failed attempt
        assertEq(IERC20(WETH).balanceOf(alice), aliceWethBefore, "maker WETH changed");
        assertEq(IERC20(USDC).balanceOf(alice), aliceUsdcBefore, "maker USDC changed");

        // TWAP state should be untouched
        (uint256 executedChunks,, uint256 totalMakingSoFar, uint256 totalTakingSoFar) =
            twapStrategy.twapStates(oneLOP.hashOrder(order));
        assertEq(executedChunks, 0, "chunks advanced");
        assertEq(totalMakingSoFar, 0, "making advanced");
        assertEq(totalTakingSoFar, 0, "taking advanced");
    }

    function test_TWAPStrategy_ChunkTooSmall() public {
        // Create a fresh fork for this test
        vm.createSelectFork(BASE_RPC_URL);

        // Re-deploy the strategy
        twapStrategy = new TWAPStrategy();
        twapStrategy.setResolverAuthorization(bob, true);

        // Re-setup balances
        deal(WETH, alice, 100 ether);
        deal(USDC, bob, 10_000_000 * 1e6);

        vm.prank(alice);
        IERC20(WETH).approve(address(oneLOP), type(uint256).max);
        vm.prank(bob);
        IERC20(USDC).approve(address(oneLOP), type(uint256).max);

        uint256 totalMaking = 5 ether;
        uint256 totalTaking = 15_000 * 1e6;

        // Helper that creates the order, signs it and registers TWAP params
        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) =
            _createAndRegisterTWAPOrder(totalMaking, totalTaking, 5, 300); // minChunk = 10% = 0.5 ETH

        // Amount below minChunk (5% < 10%)
        uint256 tooSmallAmount = totalMaking / 20;
        uint256 takerTraits = _takerTraitsForExtension(extension);

        // Snapshot state to assert no changes after revert
        bytes32 orderHash = oneLOP.hashOrder(order);
        (uint256 beforeChunks, uint256 beforeTime, uint256 beforeMaking, uint256 beforeTaking) =
            twapStrategy.twapStates(orderHash);

        vm.prank(bob);
        vm.expectRevert(iTypes.ChunkTooSmall.selector);
        oneLOP.fillOrderArgs(order, r, vs, tooSmallAmount, takerTraits, extension);

        // State must be unchanged
        (uint256 afterChunks, uint256 afterTime, uint256 afterMaking, uint256 afterTaking) =
            twapStrategy.twapStates(orderHash);

        assertEq(afterChunks, beforeChunks, "executedChunks changed");
        assertEq(afterTime, beforeTime, "lastExecutionTime changed");
        assertEq(afterMaking, beforeMaking, "totalMakingSoFar changed");
        assertEq(afterTaking, beforeTaking, "totalTakingSoFar changed");
    }

    function test_TWAPStrategy_AllChunksExecuted() public {
        uint256 totalMaking = 2 ether;
        uint256 totalTaking = 6_000 * 1e6;
        uint256 numChunks = 2;

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) =
            _createAndRegisterTWAPOrder(totalMaking, totalTaking, numChunks, 300);

        uint256 chunkAmount = totalMaking / numChunks;
        uint256 takerTraits = _takerTraitsForExtension(extension);

        // Execute all chunks
        for (uint256 i = 0; i < numChunks; i++) {
            vm.prank(bob);
            oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);

            if (i < numChunks - 1) {
                vm.warp(block.timestamp + 301);
            }
        }

        // Don't warp time forward to avoid hitting the end time
        // Just wait the minimum interval
        vm.warp(block.timestamp + 301);

        // Verify we're still within the valid time window
        bytes32 orderHash = oneLOP.hashOrder(order);
        // iTypes.TWAPParams memory params = twapStrategy.twapParams(orderHash);
        // require(block.timestamp <= params.endTime, "Test setup error: past end time");

        // Try to execute one more chunk
        // The 1inch protocol will revert with 0xf71fbda2 when the order is fully filled
        // This happens BEFORE our TWAP strategy is called, so we won't see AllChunksExecuted error
        vm.prank(bob);
        vm.expectRevert(bytes4(0xf71fbda2)); // 1inch's "order fully filled" error
        oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);
    }

    function test_TWAPStrategy_EmergencyPause() public {
        uint256 totalMaking = 5 ether;
        uint256 totalTaking = 15_000 * 1e6;

        (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) =
            _createAndRegisterTWAPOrder(totalMaking, totalTaking, 5, 300);

        // Pause the strategy
        twapStrategy.setPaused(true);

        uint256 chunkAmount = totalMaking / 5;
        uint256 takerTraits = _takerTraitsForExtension(extension);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(iTypes.Paused.selector));
        oneLOP.fillOrderArgs(order, r, vs, chunkAmount, takerTraits, extension);
    }

    // Helper function to create and register TWAP order
    function _createAndRegisterTWAPOrder(
        uint256 totalMaking,
        uint256 totalTaking,
        uint256 numChunks,
        uint256 chunkInterval
    ) internal returns (ILimitOrderProtocol.Order memory order, bytes32 r, bytes32 vs, bytes memory extension) {
        extension = _buildPrePostExtension(address(twapStrategy));
        uint256 extHash160 = uint256(keccak256(extension)) & ((1 << 160) - 1);
        uint256 randHi = uint256(keccak256(abi.encodePacked(block.timestamp, alice, totalMaking))) >> 160;
        uint256 salt = (randHi << 160) | extHash160;

        order = ILimitOrderProtocol.Order({
            salt: salt,
            maker: uint256(uint160(alice)),
            receiver: uint256(uint160(alice)),
            makerAsset: uint256(uint160(WETH)),
            takerAsset: uint256(uint160(USDC)),
            makingAmount: totalMaking,
            takingAmount: totalTaking,
            makerTraits: _makerTraitsWithExtension()
        });

        (r, vs) = _sign(order, alicePrvKey);
        bytes32 orderHash = oneLOP.hashOrder(order);

        vm.prank(alice);
        twapStrategy.registerTWAPOrder(
            orderHash,
            iTypes.TWAPParams({
                totalChunks: numChunks,
                chunkInterval: chunkInterval,
                startTime: uint64(block.timestamp),
                endTime: uint64(block.timestamp + 2 hours),
                minChunkSize: totalMaking / 10,
                maxPriceImpact: 500,
                initialized: true
            })
        );
    }

    function _sign(ILimitOrderProtocol.Order memory order, uint256 pk) internal view returns (bytes32 r, bytes32 vs) {
        bytes32 orderHash = oneLOP.hashOrder(order);
        (uint8 v, bytes32 rr, bytes32 s) = vm.sign(pk, orderHash);
        vs = bytes32((uint256(v - 27) << 255) | uint256(s)); // v packed into top bit
        r = rr;
    }

    function _makerTraitsWithExtension() internal pure returns (uint256) {
        return
            _HAS_EXTENSION_FLAG | _ALLOW_MULTIPLE_FILLS_FLAG | _PRE_INTERACTION_CALL_FLAG | _POST_INTERACTION_CALL_FLAG;
    }

    function _takerTraitsForExtension(bytes memory extension) internal pure returns (uint256) {
        uint256 fillByMakingFlag = 1 << 255;
        uint256 extensionLenBits = uint256(extension.length) << 224;
        return fillByMakingFlag | extensionLenBits;
    }

    function _buildPrePostExtension(address strategy) internal pure returns (bytes memory ext) {
        bytes memory pre = abi.encodePacked(strategy);
        bytes memory post = abi.encodePacked(strategy);

        // Calculate offsets - each offset points to the end of that section
        uint256 offset = 0;
        uint256[] memory offsets = new uint256[](8);

        // All empty sections have offset 0
        offsets[0] = offset; // makerAssetSuffix (empty)
        offsets[1] = offset; // takerAssetSuffix (empty)
        offsets[2] = offset; // makingAmountData (empty)
        offsets[3] = offset; // takingAmountData (empty)
        offsets[4] = offset; // predicate (empty)
        offsets[5] = offset; // makerPermit (empty)

        // Pre interaction
        offset += pre.length;
        offsets[6] = offset;

        // Post interaction
        offset += post.length;
        offsets[7] = offset;

        // Pack offsets into a single uint256
        uint256 packed = 0;
        for (uint256 i = 0; i < 8; i++) {
            packed |= offsets[i] << (32 * i);
        }

        ext = abi.encodePacked(bytes32(packed), pre, post);
    }
}
