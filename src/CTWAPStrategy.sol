// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "./interface/iTypes.sol";
import "./interface/iChainlink.sol";
import "./interface/i1inch.sol";

// contract cTWAPStrategy is ReentrancyGuard, Ownable, IPreInteraction, IPostInteraction, iTypes {}
contract CTWAPStrategy is iTypes, Ownable, IPreInteraction, IPostInteraction {
    using SafeERC20 for IERC20;
    // ──────────────────────────────────────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────────────────────────────────────

    /// @notice Basis-point precision used for percentage math (100% == 10_000).
    /// @dev Avoids floating-point; e.g. 50% = 5_000, 5.25% = 525.
    uint256 private constant VOLATILITY_PRECISION = 10_000;

    /// @notice Minimum spacing between executions when throttling is applied.
    /// @dev Measured in seconds. Used to rate-limit chunk fills (e.g., in
    ///      volatility/continuous modes) to prevent overly frequent executions.
    uint256 private constant MIN_EXECUTION_INTERVAL = 60; // 1 minute

    /// @notice Capacity of the ring buffer that stores recent price samples.
    /// @dev Keeps gas bounded and defines the rolling window for realized-vol
    ///      calculations. Increase for smoother stats (more gas), decrease for
    ///      cheaper updates (noisier stats).
    uint256 private constant MAX_PRICE_HISTORY = 24;

    /// @notice Cool-off period after an L2 sequencer recovers before trusting feeds.
    /// @dev Measured in seconds. Mitigates stale/unstable data immediately after
    ///      downtime on networks with sequencer uptime feeds.
    uint256 private constant GRACE_PERIOD_TIME = 3_600; // 1 hour

    /// @notice Seconds per (non-leap) year used to annualize realized volatility.
    /// @dev Converts sample-interval volatility to annualized terms.
    uint256 private constant ANNUALIZATION_FACTOR = 31_536_000;

    /// @notice Fixed-point scale (wad) for return/variance math.
    /// @dev All intermediate arithmetic is 18-decimals scaled to reduce rounding
    ///      error; use alongside helpers that expect 1e18 scaling.
    uint256 private constant FIXED_POINT_DECIMALS = 1e18;

    // To-Do: move to abstract contract
    /// @notice Rolling state used to compute realized (annualized) volatility.
    /// @dev
    /// - `priceHistory` is a fixed-size ring buffer of `PricePoint`s.
    /// - `head` is the index of the most-recently written observation (wraps around).
    /// - `count` is the number of valid observations currently stored (<= MAX_PRICE_HISTORY).
    /// - `currentVolatility` is the last computed annualized volatility, in basis points (1% = 100).
    /// - `oracleDecimals` caches the oracle feed decimals to normalize prices to 1e18.
    struct VolatilityData {
        /// @notice Fixed-size circular buffer of recent price observations.
        PricePoint[MAX_PRICE_HISTORY] priceHistory;
        /// @notice Index of the most recent entry in the ring buffer.
        uint256 head;
        /// @notice Number of valid entries in `priceHistory` (caps at MAX_PRICE_HISTORY).
        uint256 count;
        /// @notice Last computed annualized volatility (basis points).
        uint256 currentVolatility;
        /// @notice Decimals of the underlying price oracle (cached for normalization).
        uint8 oracleDecimals;
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

    /// @notice Registers a TWAP order with optional volatility controls under a unique order hash.
    /// @dev
    /// - Validates core TWAP parameters (chunk count, time window).
    /// - If volatility is enabled, validates oracle config and caches its decimals.
    /// - Persists the params and marks the order as initialized to prevent duplicates.
    /// - Optionally seeds the volatility state (ring buffer) with the first price.
    /// @param orderHash Unique identifier of the order (1inch order hash).
    /// @param params Full parameter bundle including base TWAP settings and volatility settings.
    function registerCTWAPOrder(bytes32 orderHash, CTWAPParams calldata params) external notPaused {
        // --- Core TWAP sanity checks ---
        // Must have at least one chunk.
        if (params.baseParams.totalChunks == 0) revert InvalidParameters();
        // Execution window must be forward in time (start < end).
        if (params.baseParams.startTime >= params.baseParams.endTime) revert InvalidParameters();
        // Prevent re-registration of the same order.
        if (cTwapParams[orderHash].baseParams.initialized) revert InvalidParameters();

        // --- Volatility-mode-specific validation ---
        if (params.volatilityEnabled) {
            // Max volatility threshold must be strictly greater than min.
            if (params.maxVolatility <= params.minVolatility) revert InvalidParameters();
            // A valid Chainlink price feed is required to compute realized vol.
            if (params.priceOracle == address(0)) revert InvalidParameters();
            // Must set a freshness bound for oracle data.
            if (params.maxPriceStaleness == 0) revert InvalidParameters();

            // Read and cache oracle decimals so we can normalize prices to 1e18 later.
            // If the oracle is misconfigured or the call fails, revert.
            try AggregatorV3Interface(params.priceOracle).decimals() returns (uint8 decimals) {
                volatilityData[orderHash].oracleDecimals = decimals;
            } catch {
                revert InvalidPriceFeed();
            }
        }

        // --- Persist parameters ---
        cTwapParams[orderHash] = params;
        cTwapParams[orderHash].baseParams.initialized = true;

        // --- Optional volatility bootstrap ---
        // Seed the ring buffer with an initial price, so subsequent checks have a baseline.
        if (params.volatilityEnabled) {
            _initializeVolatilityData(orderHash, params.priceOracle);
        }

        // Emit for off-chain consumers (indexers, UIs, keepers).
        emit CTWAPOrderCreated(orderHash, params);
    }

    /// @notice Gatekeeper hook called by 1inch before executing a chunk.
    /// @dev Performs all “can we execute now?” checks:
    ///      - TWAP lifecycle (chunks done? time window? spacing?)
    ///      - Optional volatility guardrail (sequencer check, price freshness, realized vol bounds)
    ///      - Chunk sizing (min chunk and volatility-adjusted target)
    ///      - Price impact protection
    ///      - Resolver authorization
    /// @param order  The 1inch order struct (making/taking totals live here)
    /// @param orderHash  Unique identifier of the order
    /// @param taker  Address attempting to execute this chunk
    /// @param makingAmount  Proposed maker amount for this fill (the “chunk” size)
    /// @param takingAmount  Proposed taker amount for this fill (can be 0 → derive expected)
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
        // Load config for this order.
        CTWAPParams memory params = cTwapParams[orderHash];

        // If not registered as a volatility TWAP order, do nothing (let LOP continue).
        if (params.baseParams.totalChunks == 0) {
            return;
        }

        // Snapshot current TWAP progress.
        TWAPState memory state = twapStates[orderHash];

        // --- Core TWAP lifecycle guards ---

        // All chunks already executed.
        if (state.executedChunks >= params.baseParams.totalChunks) {
            revert AllChunksExecuted();
        }

        // Too early (before start).
        if (block.timestamp < params.baseParams.startTime) {
            revert TooEarlyToExecute();
        }

        // Too late (after end).
        if (block.timestamp > params.baseParams.endTime) {
            revert TooLateToExecute();
        }

        // Enforce spacing between chunks unless in continuous mode.
        if (!params.continuousMode && state.executedChunks > 0) {
            uint256 interval = params.volatilityEnabled
                ? MIN_EXECUTION_INTERVAL // tighter floor if we’re in vol mode
                : params.baseParams.chunkInterval; // otherwise use configured interval

            if (block.timestamp < state.lastExecutionTime + interval) {
                revert TooEarlyToExecute();
            }
        }

        // --- Volatility guard (optional) ---
        if (params.volatilityEnabled) {
            // (Optional) L2 sequencer health check.
            if (params.sequencerOracle != address(0)) {
                _checkSequencerUptime(params.sequencerOracle);
            }

            // Pull latest price, update ring buffer, recompute realized vol (annualized, bps).
            _updateVolatilityData(orderHash, params);
            uint256 currentVol = volatilityData[orderHash].currentVolatility;

            // Must be inside the user’s safe range.
            if (currentVol < params.minVolatility) {
                revert VolatilityTooLow(currentVol, params.minVolatility);
            }
            if (currentVol > params.maxVolatility) {
                revert VolatilityTooHigh(currentVol, params.maxVolatility);
            }
        }

        // --- Chunk sizing (with optional volatility adjustment) ---
        uint256 expectedChunkSize = _calculateVolatilityAdjustedChunkSize(
            orderHash, // used for event/context in your implementation
            order.makingAmount, // total maker amount in the order
            params,
            state.executedChunks,
            volatilityData[orderHash].currentVolatility
        );

        // Reject too-small chunks. We allow smaller than the base target only if
        // it still satisfies the configured minChunkSize OR matches the adjusted target.
        if (makingAmount < params.baseParams.minChunkSize && makingAmount < expectedChunkSize) {
            revert ChunkTooSmall();
        }

        // --- Price impact protection ---
        if (params.baseParams.maxPriceImpact > 0) {
            // Pro-rata expectation: taking should scale with making.
            uint256 expectedTakingForChunk = (order.takingAmount * makingAmount) / order.makingAmount;
            // If taker didn’t pass a taking amount (or passed 0), compare against expectation.
            uint256 actualTaking = takingAmount > 0 ? takingAmount : expectedTakingForChunk;

            uint256 impactBps = calculatePriceImpact(expectedTakingForChunk, actualTaking);
            if (impactBps > params.baseParams.maxPriceImpact) {
                revert PriceImpactTooHigh();
            }
        }

        // --- Authorization: only approved resolvers (or owner) may execute ---
        if (!authorizedResolvers[taker] && taker != owner()) {
            revert Unauthorized();
        }

        // If we reach here, all checks passed; 1inch can proceed with the fill.
    }

    /// @notice Called by 1inch after a chunk has been filled successfully.
    /// @dev Updates TWAP progress (counters, timestamps, totals) and emits events.
    ///      If all chunks are done (or the order is fully consumed), also emits completion.
    /// @param order           The original 1inch order (unused here, but part of the hook signature)
    /// @param orderHash       Unique identifier tying this call to stored TWAP params/state
    /// @param makingAmount    Maker amount actually filled in this chunk
    /// @param takingAmount    Taker amount actually received in this chunk
    /// @param remainingAmount Remaining maker amount left in the 1inch order after this fill
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
        // If this order was not registered as a volatility TWAP, do nothing.
        CTWAPParams memory params = cTwapParams[orderHash];
        if (params.baseParams.totalChunks == 0) {
            return;
        }

        // Load the mutable TWAP state for this order.
        TWAPState storage state = twapStates[orderHash];

        // 1) Count this executed chunk.
        state.executedChunks++;

        // 2) Track when it happened (used to enforce spacing for the next chunk).
        state.lastExecutionTime = block.timestamp;

        // 3) Accumulate actual amounts filled so far.
        state.totalMakingAmount += makingAmount;
        state.totalTakingAmount += takingAmount;

        // 4) Announce progress to off-chain listeners (indexers, bots, UIs).
        emit TWAPChunkExecuted(orderHash, state.executedChunks, makingAmount, takingAmount);

        // 5) If we reached the target number of chunks OR the order is fully consumed on 1inch,
        //    emit a completion event for clean downstream handling.
        if (state.executedChunks >= params.baseParams.totalChunks || remainingAmount == 0) {
            emit TWAPOrderCompleted(orderHash, state.totalMakingAmount, state.totalTakingAmount);
        }
    }

    // Check Arbitrum sequencer uptime with grace period
    function _checkSequencerUptime(address sequencerUptimeFeed) internal view {
        (, int256 answer, uint256 startedAt,,) = AggregatorV3Interface(sequencerUptimeFeed).latestRoundData();

        // 0 = up, 1 = down
        if (answer != 0) {
            revert SequencerDown();
        }

        // Enforce a grace period after sequencer comes back up
        if (block.timestamp - startedAt <= GRACE_PERIOD_TIME) {
            revert PriceFeedStale(block.timestamp - startedAt, GRACE_PERIOD_TIME);
        }
    }

    // Update volatility data with new price
    function _updateVolatilityData(bytes32 orderHash, CTWAPParams memory params) internal {
        (uint80 roundId, int256 price,, uint256 updatedAt,) =
            AggregatorV3Interface(params.priceOracle).latestRoundData();

        // Check price validity and staleness
        if (price <= 0 || roundId == 0 || updatedAt == 0) {
            revert InvalidPriceFeed();
        }

        uint256 staleness = block.timestamp - updatedAt;
        if (staleness > params.maxPriceStaleness) {
            revert PriceFeedStale(staleness, params.maxPriceStaleness);
        }

        VolatilityData storage volData = volatilityData[orderHash];
        uint256 normalizedPrice = _normalizePrice(uint256(price), volData.oracleDecimals);

        // Only update if enough time has passed
        uint256 lastTimestamp = volData.priceHistory[volData.head].timestamp;
        if (block.timestamp <= lastTimestamp) {
            return;
        }

        // Calculate signed return
        uint256 lastPrice = volData.priceHistory[volData.head].price;
        int256 returnWad = _signedReturnWad(lastPrice, normalizedPrice);

        // Move to next position in ring buffer
        uint256 nextHead = (volData.head + 1) % MAX_PRICE_HISTORY;

        // Update count if buffer not full
        if (volData.count < MAX_PRICE_HISTORY) {
            volData.count++;
        }

        // Add new price point
        volData.priceHistory[nextHead] =
            PricePoint({price: normalizedPrice, timestamp: block.timestamp, returnWad: returnWad});

        volData.head = nextHead;

        // Calculate volatility if we have enough data points
        if (volData.count >= 2) {
            volData.currentVolatility = _calculateRealizedVolatility(orderHash, params.volatilityWindow);
            emit VolatilityUpdate(orderHash, volData.currentVolatility, normalizedPrice, block.timestamp);
        }
    }

    // Calculate realized volatility using proper statistical methods
    function _calculateRealizedVolatility(bytes32 orderHash, uint256 timeWindow) internal view returns (uint256) {
        VolatilityData storage volData = volatilityData[orderHash];

        if (volData.count < 2) return 0;

        uint256 validReturns = 0;
        int256 sumReturns = 0;
        uint256 sumSquaredReturns = 0;
        uint256 oldestValidTimestamp = block.timestamp > timeWindow ? block.timestamp - timeWindow : 0;
        uint256 firstIncludedTimestamp = 0;
        uint256 lastIncludedTimestamp = 0;

        // Iterate through ring buffer
        for (uint256 i = 0; i < volData.count - 1; i++) {
            uint256 idx = (volData.head + MAX_PRICE_HISTORY - i) % MAX_PRICE_HISTORY;
            PricePoint memory point = volData.priceHistory[idx];

            // Only include points within time window
            if (point.timestamp < oldestValidTimestamp) break;
            if (point.returnWad == 0) continue;

            validReturns++;
            sumReturns += point.returnWad;
            sumSquaredReturns += uint256((point.returnWad * point.returnWad) / int256(FIXED_POINT_DECIMALS));

            // Track time bounds
            if (firstIncludedTimestamp == 0 || point.timestamp < firstIncludedTimestamp) {
                firstIncludedTimestamp = point.timestamp;
            }
            if (point.timestamp > lastIncludedTimestamp) {
                lastIncludedTimestamp = point.timestamp;
            }
        }

        if (validReturns == 0) return 0;

        // Calculate variance using standard formula: Var = E[X²] - E[X]²
        int256 meanReturn = sumReturns / int256(validReturns);
        uint256 variance =
            (sumSquaredReturns / validReturns) - uint256((meanReturn * meanReturn) / int256(FIXED_POINT_DECIMALS));

        // Standard deviation = sqrt(variance)
        uint256 stdDev = _sqrt(variance * FIXED_POINT_DECIMALS);

        // Annualize volatility
        uint256 timeSpan = lastIncludedTimestamp - firstIncludedTimestamp;
        if (timeSpan == 0) return 0;

        uint256 avgTimeBetweenSamples = timeSpan / validReturns;
        uint256 annualizationFactor = _sqrt((ANNUALIZATION_FACTOR * FIXED_POINT_DECIMALS) / avgTimeBetweenSamples);

        // Return annualized volatility in basis points
        return (stdDev * annualizationFactor * VOLATILITY_PRECISION) / (FIXED_POINT_DECIMALS * FIXED_POINT_DECIMALS);
    }

    // Calculate signed return (new - old) / old, scaled by FIXED_POINT_DECIMALS
    function _signedReturnWad(uint256 oldPrice, uint256 newPrice) internal pure returns (int256) {
        if (oldPrice == 0 || newPrice == 0) return 0;

        // (new - old) / old, 1e18-scaled and signed
        return (int256(newPrice) - int256(oldPrice)) * int256(FIXED_POINT_DECIMALS) / int256(oldPrice);
    }

    // Initialize volatility tracking
    function _initializeVolatilityData(bytes32 orderHash, address priceOracle) internal {
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(priceOracle).latestRoundData();

        if (price <= 0) revert InvalidPriceFeed();

        VolatilityData storage volData = volatilityData[orderHash];

        // Initialize first price point
        volData.priceHistory[0] = PricePoint({
            price: _normalizePrice(uint256(price), volData.oracleDecimals),
            timestamp: block.timestamp,
            returnWad: 0
        });

        volData.head = 0;
        volData.count = 1;
        volData.currentVolatility = 0;
    }

    // Normalize price to standard decimals (18)
    function _normalizePrice(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return price;
        if (decimals < 18) {
            return price * 10 ** (18 - decimals);
        } else {
            return price / 10 ** (decimals - 18);
        }
    }

    // Square root using Babylonian method
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
            uint256 currentVol = volatilityData[orderHash].currentVolatility;
            if (currentVol < params.minVolatility) {
                return (false, "Volatility too low");
            }
            if (currentVol > params.maxVolatility) {
                return (false, "Volatility too high");
            }
        }

        return (true, "Can execute");
    }

    function getCurrentVolatility(bytes32 orderHash) external view returns (uint256) {
        return volatilityData[orderHash].currentVolatility;
    }

    // Calculate volatility-adjusted chunk size
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

        // Adjust chunk size based on volatility
        // Higher volatility = smaller chunks for risk management
        uint256 adjustmentFactor = VOLATILITY_PRECISION;

        if (currentVolatility > params.minVolatility) {
            uint256 volRange = params.maxVolatility - params.minVolatility;
            uint256 volPosition = currentVolatility - params.minVolatility;

            // Linear adjustment: at max volatility, chunk size is 50% of base
            // At min volatility, chunk size is 100% of base
            adjustmentFactor = VOLATILITY_PRECISION - (volPosition * 5000 / volRange);
        }

        uint256 adjustedSize = (baseChunkSize * adjustmentFactor) / VOLATILITY_PRECISION;

        emit ChunkSizeAdjusted(orderHash, baseChunkSize, adjustedSize, currentVolatility);

        return adjustedSize;
    }

    function getPriceHistory(bytes32 orderHash)
        external
        view
        returns (uint256[] memory prices, uint256[] memory timestamps, uint256 currentIndex)
    {
        VolatilityData storage volData = volatilityData[orderHash];
        uint256 count = volData.count;

        prices = new uint256[](count);
        timestamps = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 idx = (volData.head + MAX_PRICE_HISTORY - i) % MAX_PRICE_HISTORY;
            prices[i] = volData.priceHistory[idx].price;
            timestamps[i] = volData.priceHistory[idx].timestamp;
        }

        currentIndex = volData.head;
    }

    // Existing helper functions
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
