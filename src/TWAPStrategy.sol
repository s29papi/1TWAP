// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interface/i1inch.sol";
import "./interface/iTypes.sol";
import {console} from "forge-std/Test.sol";

contract TWAPStrategy is ReentrancyGuard, Ownable, IPreInteraction, IPostInteraction, iTypes {
    using SafeERC20 for IERC20;

    // Mapping from order hash to TWAP parameters
    mapping(bytes32 => TWAPParams) public twapParams;

    // Mapping from order hash to TWAP execution state
    mapping(bytes32 => TWAPState) public twapStates;

    // Authorized resolvers who can execute TWAP chunks
    mapping(address => bool) public authorizedResolvers;

    // Emergency pause
    bool public paused;

    modifier notPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier onlyAuthorizedResolver() {
        if (!authorizedResolvers[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setResolverAuthorization(address resolver, bool authorized) external onlyOwner {
        authorizedResolvers[resolver] = authorized;
        emit ResolverAuthorized(resolver, authorized);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit EmergencyPause(_paused);
    }

    function registerTWAPOrder(bytes32 orderHash, TWAPParams calldata params) external notPaused {
        if (params.totalChunks == 0 || params.chunkInterval == 0) {
            revert InvalidParameters();
        }
        if (params.startTime >= params.endTime) {
            revert InvalidParameters();
        }
        if (twapParams[orderHash].initialized) {
            revert InvalidParameters(); // Order already registered
        }

        twapParams[orderHash] = params;
        twapParams[orderHash].initialized = true;
        emit TWAPOrderCreated(orderHash, params);
    }

    function preInteraction(
        IOrderMixin.Order memory order,
        bytes memory, /* extension */
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256, /* remainingAmount */
        bytes memory /* extraData */
    ) external override notPaused {
        TWAPParams memory params = twapParams[orderHash];
        if (params.totalChunks == 0) {
            return; // Not a TWAP order, skip validation
        }

        TWAPState memory state = twapStates[orderHash];

        console.log(state.executedChunks);
        console.log(params.totalChunks);

        if (state.executedChunks >= params.totalChunks) {
            revert AllChunksExecuted();
        }

        if (block.timestamp < params.startTime) {
            revert TooEarlyToExecute();
        }

        if (block.timestamp > params.endTime) {
            revert TooLateToExecute();
        }

        if (state.executedChunks > 0) {
            if (block.timestamp < state.lastExecutionTime + params.chunkInterval) {
                revert TooEarlyToExecute();
            }
        }

        // Check chunk size
        uint256 expectedChunkSize = calculateChunkSize(order.makingAmount, params.totalChunks, state.executedChunks);

        if (makingAmount < params.minChunkSize && makingAmount < expectedChunkSize) {
            revert ChunkTooSmall();
        }

        // Fixed price impact calculation
        if (params.maxPriceImpact > 0) {
            // For fillByMaking, the takingAmount parameter represents what the taker will receive
            // We need to check if this deviates from the expected proportional amount

            // Calculate the expected taking amount for this chunk based on the original price
            uint256 expectedTakingAmountForChunk = (order.takingAmount * makingAmount) / order.makingAmount;

            // The actual taking amount the maker will pay (taker receives)
            // In fillByMaking mode, if takingAmount is 0, it means use the proportional amount
            uint256 actualTakingAmount = takingAmount > 0 ? takingAmount : expectedTakingAmountForChunk;

            // Calculate price impact
            uint256 priceImpact = calculatePriceImpact(expectedTakingAmountForChunk, actualTakingAmount);

            if (priceImpact > params.maxPriceImpact) {
                revert PriceImpactTooHigh();
            }
        }

        // Only authorized resolvers can execute TWAP orders
        if (!authorizedResolvers[taker] && taker != owner()) {
            revert Unauthorized();
        }
    }

    function postInteraction(
        IOrderMixin.Order memory order,
        bytes memory, /* extension */
        bytes32 orderHash,
        address, /* taker */
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingAmount,
        bytes memory /* extraData */
    ) external override {
        TWAPParams memory params = twapParams[orderHash];
        if (params.totalChunks == 0) {
            return; // Not a TWAP order
        }

        TWAPState storage state = twapStates[orderHash];

        // Update state
        state.executedChunks++;
        state.lastExecutionTime = block.timestamp;
        state.totalMakingAmount += makingAmount;
        state.totalTakingAmount += takingAmount;

        emit TWAPChunkExecuted(orderHash, state.executedChunks, makingAmount, takingAmount);

        // Check if order is completed
        if (state.executedChunks >= params.totalChunks || remainingAmount == 0) {
            emit TWAPOrderCompleted(orderHash, state.totalMakingAmount, state.totalTakingAmount);
        }
    }

    function calculateChunkSize(uint256 totalAmount, uint256 totalChunks, uint256 executedChunks)
        public
        pure
        returns (uint256)
    {
        uint256 remainingChunks = totalChunks - executedChunks;
        if (remainingChunks == 0) return 0;

        uint256 baseChunkSize = totalAmount / totalChunks;
        uint256 remainder = totalAmount % totalChunks;

        // Add remainder to last chunk
        if (remainingChunks == 1) {
            return baseChunkSize + remainder;
        }

        return baseChunkSize;
    }

    function calculatePriceImpact(uint256 expectedAmount, uint256 actualAmount) public pure returns (uint256) {
        if (expectedAmount == 0) return 0;

        uint256 diff = actualAmount > expectedAmount ? actualAmount - expectedAmount : expectedAmount - actualAmount;

        return (diff * 10000) / expectedAmount; // Return in basis points
    }

    function canExecuteChunk(bytes32 orderHash) external view returns (bool) {
        TWAPParams memory params = twapParams[orderHash];
        if (params.totalChunks == 0) return false;

        TWAPState memory state = twapStates[orderHash];
        if (state.executedChunks >= params.totalChunks) return false;

        if (block.timestamp < params.startTime || block.timestamp > params.endTime) {
            return false;
        }

        if (state.executedChunks > 0 && block.timestamp < state.lastExecutionTime + params.chunkInterval) {
            return false;
        }

        return true;
    }

    function getNextExecutionTime(bytes32 orderHash) external view returns (uint256) {
        TWAPParams memory params = twapParams[orderHash];
        TWAPState memory state = twapStates[orderHash];

        if (params.totalChunks == 0 || state.executedChunks >= params.totalChunks) {
            return 0;
        }

        if (state.executedChunks == 0) {
            return params.startTime;
        }

        return state.lastExecutionTime + params.chunkInterval;
    }
}
