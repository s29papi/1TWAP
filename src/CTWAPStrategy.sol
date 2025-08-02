// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "./interface/iTypes.sol";
import "./interface/iChainlink.sol";
import "./interface/i1inch.sol";

contract CTWAPStrategy is iTypes, Ownable, IPreInteraction, IPostInteraction {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant VOLATILITY_PRECISION = 10_000;
    uint256 private constant MIN_EXECUTION_INTERVAL = 60;
    uint256 private constant GRACE_PERIOD_TIME = 3_600;
    uint256 private constant FIXED_POINT_DECIMALS = 1e18;

    // Modified struct - remove historical tracking
    struct VolatilityData {
        address volatilityOracle; // Direct volatility oracle address
        uint8 priceOracleDecimals; // Still need for price impact checks
        uint256 lastKnownVolatility; // Cache last known value
        uint256 lastUpdateTime;
    }

    // Mappings
    mapping(bytes32 => CTWAPParams) public cTwapParams;
    mapping(bytes32 => TWAPState) public twapStates;
    mapping(bytes32 => VolatilityData) public volatilityData;
    mapping(address => bool) public authorizedResolvers;

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

    function registerCTWAPOrder(bytes32 orderHash, CTWAPParams calldata params) external notPaused {
        // Core TWAP sanity checks
        if (params.baseParams.totalChunks == 0) revert InvalidParameters();
        if (params.baseParams.startTime >= params.baseParams.endTime) revert InvalidParameters();
        if (cTwapParams[orderHash].baseParams.initialized) revert InvalidParameters();

        // Volatility-mode-specific validation
        if (params.volatilityEnabled) {
            if (params.maxVolatility <= params.minVolatility) revert InvalidParameters();

            // For real-time volatility, we need either:
            // 1. A dedicated volatility oracle (preferred)
            // 2. A price oracle from which we can derive instant volatility
            if (params.priceOracle == address(0) && params.volatilityOracle == address(0)) {
                revert InvalidParameters();
            }

            if (params.maxPriceStaleness == 0) revert InvalidParameters();

            // If using price oracle, cache its decimals
            if (params.priceOracle != address(0)) {
                try AggregatorV3Interface(params.priceOracle).decimals() returns (uint8 decimals) {
                    volatilityData[orderHash].priceOracleDecimals = decimals;
                } catch {
                    revert InvalidPriceFeed();
                }
            }

            // Store volatility oracle if provided
            if (params.volatilityOracle != address(0)) {
                volatilityData[orderHash].volatilityOracle = params.volatilityOracle;
            }
        }

        // Persist parameters
        cTwapParams[orderHash] = params;
        cTwapParams[orderHash].baseParams.initialized = true;

        emit CTWAPOrderCreated(orderHash, params);
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
        CTWAPParams memory params = cTwapParams[orderHash];
        if (params.baseParams.totalChunks == 0) return;

        TWAPState memory state = twapStates[orderHash];

        // Core TWAP lifecycle guards
        if (state.executedChunks >= params.baseParams.totalChunks) {
            revert AllChunksExecuted();
        }
        if (block.timestamp < params.baseParams.startTime) {
            revert TooEarlyToExecute();
        }
        if (block.timestamp > params.baseParams.endTime) {
            revert TooLateToExecute();
        }

        // Enforce spacing between chunks
        if (!params.continuousMode && state.executedChunks > 0) {
            uint256 interval = params.volatilityEnabled ? MIN_EXECUTION_INTERVAL : params.baseParams.chunkInterval;

            if (block.timestamp < state.lastExecutionTime + interval) {
                revert TooEarlyToExecute();
            }
        }

        // Real-time volatility guard
        if (params.volatilityEnabled) {
            // Optional L2 sequencer health check
            if (params.sequencerOracle != address(0)) {
                _checkSequencerUptime(params.sequencerOracle);
            }

            // Get real-time volatility
            uint256 currentVol = _getRealTimeVolatility(orderHash, params);

            // Update cache
            volatilityData[orderHash].lastKnownVolatility = currentVol;
            volatilityData[orderHash].lastUpdateTime = block.timestamp;

            // Check volatility bounds
            if (currentVol < params.minVolatility) {
                revert VolatilityTooLow(currentVol, params.minVolatility);
            }
            if (currentVol > params.maxVolatility) {
                revert VolatilityTooHigh(currentVol, params.maxVolatility);
            }

            emit VolatilityUpdate(orderHash, currentVol, 0, block.timestamp);
        }

        // Chunk sizing with volatility adjustment
        uint256 expectedChunkSize = _calculateVolatilityAdjustedChunkSize(
            orderHash, order.makingAmount, params, state.executedChunks, volatilityData[orderHash].lastKnownVolatility
        );

        if (makingAmount < params.baseParams.minChunkSize && makingAmount < expectedChunkSize) {
            revert ChunkTooSmall();
        }

        // Price impact protection
        if (params.baseParams.maxPriceImpact > 0) {
            uint256 expectedTakingForChunk = (order.takingAmount * makingAmount) / order.makingAmount;
            uint256 actualTaking = takingAmount > 0 ? takingAmount : expectedTakingForChunk;
            uint256 impactBps = calculatePriceImpact(expectedTakingForChunk, actualTaking);

            if (impactBps > params.baseParams.maxPriceImpact) {
                revert PriceImpactTooHigh();
            }
        }

        // Authorization check
        if (!authorizedResolvers[taker] && taker != owner()) {
            revert Unauthorized();
        }
    }

    function postInteraction(
        IOrderMixin.Order memory order,
        bytes memory,
        bytes32 orderHash,
        address,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingAmount,
        bytes memory
    ) external override {
        CTWAPParams memory params = cTwapParams[orderHash];
        if (params.baseParams.totalChunks == 0) return;

        TWAPState storage state = twapStates[orderHash];
        state.executedChunks++;
        state.lastExecutionTime = block.timestamp;
        state.totalMakingAmount += makingAmount;
        state.totalTakingAmount += takingAmount;

        emit TWAPChunkExecuted(orderHash, state.executedChunks, makingAmount, takingAmount);

        if (state.executedChunks >= params.baseParams.totalChunks || remainingAmount == 0) {
            emit TWAPOrderCompleted(orderHash, state.totalMakingAmount, state.totalTakingAmount);
        }
    }

    // Get real-time volatility from oracle or calculate instant volatility
    function _getRealTimeVolatility(bytes32 orderHash, CTWAPParams memory params) internal view returns (uint256) {
        VolatilityData memory volData = volatilityData[orderHash];

        // Option 1: Use dedicated volatility oracle if available
        if (volData.volatilityOracle != address(0)) {
            try IVolatilityOracle(volData.volatilityOracle).latestVolatility() returns (uint256 vol) {
                // Convert to basis points if needed
                return vol;
            } catch {
                try IVolatilityOracle(volData.volatilityOracle).getImpliedVolatility(params.makerAsset) returns (
                    uint256 vol
                ) {
                    return vol;
                } catch {
                    // Fallback to instant volatility calculation
                }
            }
        }

        // Option 2: Calculate instant volatility from price movements
        if (params.priceOracle != address(0)) {
            return _calculateInstantVolatility(params.priceOracle, volData.priceOracleDecimals);
        }

        // Option 3: Use a default volatility value or revert
        revert("No volatility source available");
    }

    // Calculate instant volatility from recent price movements
    function _calculateInstantVolatility(address priceOracle, uint8 decimals) internal view returns (uint256) {
        // Get current price
        (uint80 currentRoundId, int256 currentPrice,, uint256 currentTime,) =
            AggregatorV3Interface(priceOracle).latestRoundData();
        if (currentPrice <= 0) revert InvalidPriceFeed();

        // Try to get previous round for instant calculation
        if (currentRoundId > 0) {
            try AggregatorV3Interface(priceOracle).getRoundData(currentRoundId - 1) returns (
                uint80, int256 prevPrice, uint256, uint256 prevTime, uint80
            ) {
                if (prevPrice <= 0 || prevTime >= currentTime || prevTime == 0) {
                    // If no valid previous data, return a default medium volatility
                    return 2000; // 20% annualized
                }

                // Calculate instant return
                uint256 timeDiff = currentTime - prevTime;
                if (timeDiff == 0) return 2000; // Default if same timestamp

                // Normalize prices to 18 decimals for precision
                uint256 normalizedCurrent = _normalizePrice(uint256(currentPrice), decimals);
                uint256 normalizedPrev = _normalizePrice(uint256(prevPrice), decimals);

                // Calculate absolute return with higher precision
                uint256 priceDiff = normalizedCurrent > normalizedPrev
                    ? normalizedCurrent - normalizedPrev
                    : normalizedPrev - normalizedCurrent;

                // If price hasn't changed much, calculate based on typical volatility
                if (priceDiff == 0 || (priceDiff * FIXED_POINT_DECIMALS) / normalizedPrev < 1e14) {
                    // Price moved less than 0.01%, use historical average volatility
                    // ETH typically ~60-80% annualized, BTC ~50-70%
                    return 6000; // 60% default for crypto
                }

                // Calculate return as a fraction
                uint256 absReturn = (priceDiff * FIXED_POINT_DECIMALS) / normalizedPrev;

                // Annualize based on the time between updates
                // Most Chainlink feeds update every hour (3600 seconds)
                uint256 periodsPerYear = 365 days / timeDiff;

                // Apply square root of periods for annualization
                // This is a simplified calculation: annualized_vol = return * sqrt(periods_per_year)
                uint256 sqrtPeriods = _sqrt(periodsPerYear);
                uint256 annualizedVol = (absReturn * sqrtPeriods);

                // Convert to basis points (multiply by 10000 and divide by 1e18)
                uint256 volBps = (annualizedVol * VOLATILITY_PRECISION) / FIXED_POINT_DECIMALS;

                // Ensure reasonable bounds (1% to 500%)
                if (volBps < 100) return 100;
                if (volBps > 50000) return 50000;

                return volBps;
            } catch {
                // If getRoundData fails, return default
                return 6000; // 60% default volatility for crypto
            }
        }

        // If no previous round available
        return 6000; // 60% default volatility for crypto
    }

    // Check sequencer uptime
    function _checkSequencerUptime(address sequencerUptimeFeed) internal view {
        (, int256 answer, uint256 startedAt,,) = AggregatorV3Interface(sequencerUptimeFeed).latestRoundData();
        if (answer != 0) revert SequencerDown();
        if (block.timestamp - startedAt <= GRACE_PERIOD_TIME) {
            revert PriceFeedStale(block.timestamp - startedAt, GRACE_PERIOD_TIME);
        }
    }

    // Helper functions
    function _normalizePrice(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return price;
        if (decimals < 18) {
            return price * 10 ** (18 - decimals);
        } else {
            return price / 10 ** (decimals - 18);
        }
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function getCurrentVolatility(bytes32 orderHash) external view returns (uint256) {
        CTWAPParams memory params = cTwapParams[orderHash];
        if (!params.volatilityEnabled) return 0;

        // Try to get fresh volatility
        try this.getRealTimeVolatility(orderHash, params) returns (uint256 vol) {
            return vol;
        } catch {
            // Return cached value if available
            return volatilityData[orderHash].lastKnownVolatility;
        }
    }

    // Public wrapper for external calls
    function getRealTimeVolatility(bytes32 orderHash, CTWAPParams memory params) public view returns (uint256) {
        return _getRealTimeVolatility(orderHash, params);
    }

    function canExecuteVolatilityChunk(bytes32 orderHash) external view returns (bool, string memory reason) {
        CTWAPParams memory params = cTwapParams[orderHash];
        if (params.baseParams.totalChunks == 0) return (false, "Not a volatility TWAP order");

        TWAPState memory state = twapStates[orderHash];
        if (state.executedChunks >= params.baseParams.totalChunks) {
            return (false, "All chunks executed");
        }

        if (block.timestamp < params.baseParams.startTime) {
            return (false, "Too early to start");
        }

        if (block.timestamp > params.baseParams.endTime) {
            return (false, "Order expired");
        }

        if (!params.continuousMode && state.executedChunks > 0) {
            uint256 minInterval = params.volatilityEnabled ? MIN_EXECUTION_INTERVAL : params.baseParams.chunkInterval;
            if (block.timestamp < state.lastExecutionTime + minInterval) {
                return (false, "Too early for next chunk");
            }
        }

        if (params.volatilityEnabled) {
            try this.getRealTimeVolatility(orderHash, params) returns (uint256 currentVol) {
                if (currentVol < params.minVolatility) {
                    return (false, "Volatility too low");
                }
                if (currentVol > params.maxVolatility) {
                    return (false, "Volatility too high");
                }
            } catch {
                return (false, "Failed to get volatility");
            }
        }

        return (true, "Can execute");
    }

    function _calculateVolatilityAdjustedChunkSize(
        bytes32 orderHash,
        uint256 totalAmount,
        CTWAPParams memory params,
        uint256 executedChunks,
        uint256 currentVolatility
    ) internal returns (uint256) {
        uint256 baseChunkSize = calculateChunkSize(totalAmount, params.baseParams.totalChunks, executedChunks);

        if (!params.volatilityEnabled || !params.adaptiveChunkSize) {
            return baseChunkSize;
        }

        uint256 adjustmentFactor = VOLATILITY_PRECISION;
        if (currentVolatility > params.minVolatility) {
            uint256 volRange = params.maxVolatility - params.minVolatility;
            uint256 volPosition = currentVolatility - params.minVolatility;
            adjustmentFactor = VOLATILITY_PRECISION - (volPosition * 5000 / volRange);
        }

        uint256 adjustedSize = (baseChunkSize * adjustmentFactor) / VOLATILITY_PRECISION;
        emit ChunkSizeAdjusted(orderHash, baseChunkSize, adjustedSize, currentVolatility);
        return adjustedSize;
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

        if (remainingChunks == 1) {
            return baseChunkSize + remainder;
        }
        return baseChunkSize;
    }

    function calculatePriceImpact(uint256 expectedAmount, uint256 actualAmount) public pure returns (uint256) {
        if (expectedAmount == 0) return 0;
        uint256 diff = actualAmount > expectedAmount ? actualAmount - expectedAmount : expectedAmount - actualAmount;
        return (diff * 10000) / expectedAmount;
    }

    function getNextExecutionTime(bytes32 orderHash) external view returns (uint256) {
        CTWAPParams memory params = cTwapParams[orderHash];
        TWAPState memory state = twapStates[orderHash];

        if (params.baseParams.totalChunks == 0 || state.executedChunks >= params.baseParams.totalChunks) {
            return 0;
        }

        if (state.executedChunks == 0) {
            return params.baseParams.startTime;
        }

        if (params.continuousMode && params.volatilityEnabled) {
            return state.lastExecutionTime + MIN_EXECUTION_INTERVAL;
        }

        return state.lastExecutionTime + params.baseParams.chunkInterval;
    }
}
