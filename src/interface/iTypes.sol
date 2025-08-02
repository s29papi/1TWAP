// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface iTypes {
    // Events
    event TWAPOrderCreated(bytes32 indexed orderHash, TWAPParams params);
    event TWAPChunkExecuted(bytes32 indexed orderHash, uint256 chunkNumber, uint256 makingAmount, uint256 takingAmount);
    event TWAPOrderCompleted(bytes32 indexed orderHash, uint256 totalMakingAmount, uint256 totalTakingAmount);
    event ResolverAuthorized(address indexed resolver, bool authorized);
    event EmergencyPause(bool paused);

    // Events
    event CTWAPOrderCreated(bytes32 indexed orderHash, CTWAPParams params);

    event VolatilityUpdate(bytes32 indexed orderHash, uint256 annualizedVolatility, uint256 price, uint256 timestamp);

    event ChunkSizeAdjusted(bytes32 indexed orderHash, uint256 originalSize, uint256 adjustedSize, uint256 volatility);

    event PriceDataRejected(bytes32 indexed orderHash, string reason);

    // Custom errors
    error VolatilityTooLow(uint256 current, uint256 minimum);
    error VolatilityTooHigh(uint256 current, uint256 maximum);
    error PriceFeedStale(uint256 staleness, uint256 maxStaleness);
    error SequencerDown();
    error InvalidPriceFeed();

    // Errors
    error InvalidParameters();
    error AllChunksExecuted();
    error TooEarlyToExecute();
    error TooLateToExecute();
    error ChunkTooSmall();
    error PriceImpactTooHigh();
    error Unauthorized();
    error Paused();

    struct TWAPParams {
        uint256 totalChunks;
        uint256 chunkInterval;
        uint64 startTime;
        uint64 endTime;
        uint256 minChunkSize;
        uint256 maxPriceImpact;
        bool initialized;
    }

    struct TWAPState {
        uint256 executedChunks;
        uint256 lastExecutionTime;
        uint256 totalMakingAmount;
        uint256 totalTakingAmount;
    }

    /// @notice Single observation in the rolling price history ring buffer.
    /// @dev
    /// - `price` is normalized to 18 decimals (see `_normalizePrice`) to keep units consistent.
    /// - `returnWad` is the signed fractional return from the *previous* observation:
    ///      returnWad = (price_now - price_prev) / price_prev, scaled by 1e18.
    ///   Example: +1% => 0.01e18;  -0.5% => -0.005e18.
    /// - The first observation after initialization typically has `returnWad == 0`
    ///   because there is no prior point.
    /// - These precomputed returns are consumed by the volatility calculator to
    ///   derive mean, variance, and annualized volatility without re-diffing prices.
    struct PricePoint {
        /// @notice Normalized asset price (1e18-scaled).
        uint256 price;
        /// @notice Block timestamp when `price` was observed.
        uint256 timestamp;
        /// @notice Signed fractional return from the previous point, 1e18 fixed-point.
        /// @dev Positive for price increases, negative for price decreases.
        int256 returnWad;
    }

    /// @notice Configuration for a TWAP order that adapts to market volatility.
    /// @dev Combines the base TWAP schedule/limits with oracle-driven constraints
    ///      and optional adaptive behavior. Stored per orderHash at registration.
    struct CTWAPParams {
        /// @notice Core TWAP parameters (chunks, timing, min size, price impact, etc.).
        /// @dev Must have baseParams.initialized == true after registration.
        TWAPParams baseParams;
        /// @notice Enable/disable volatility gating and adaptive features.
        bool volatilityEnabled;
        /// @notice Lower volatility bound to allow execution (annualized, in bps).
        /// @dev Example: 800 == 8% annualized realized vol. If current vol < minVolatility,
        ///      execution reverts (market considered “too calm” if you want movement).
        uint256 minVolatility;
        /// @notice Upper volatility bound to allow execution (annualized, in bps).
        /// @dev Example: 3000 == 30% annualized. If current vol > maxVolatility,
        ///      execution reverts (market considered “too turbulent”).
        uint256 maxVolatility;
        /// @notice Lookback window (seconds) used when computing realized volatility.
        /// @dev The contract aggregates recent oracle prices within this window.
        uint256 volatilityWindow;
        /// @notice Chainlink feed used to fetch the underlying price series.
        /// @dev Must be a valid AggregatorV3Interface with fresh, positive answers.
        address priceOracle;
        /// @notice Optional L2 sequencer uptime feed (e.g., Arbitrum).
        /// @dev If set, execution verifies sequencer is up and may enforce a grace period.
        address sequencerOracle;
        /// @notice Maximum allowable staleness of the priceOracle update (seconds).
        /// @dev If (block.timestamp - updatedAt) > maxPriceStaleness, execution reverts.
        uint256 maxPriceStaleness;
        /// @notice If true, dynamically scale per-chunk size based on current volatility.
        /// @dev Typical policy: higher vol → smaller chunks; lower vol → larger chunks.
        bool adaptiveChunkSize;
        /// @notice If true, allow near-continuous execution when conditions permit.
        /// @dev Replaces the standard TWAP interval with a shorter safety interval to
        ///      avoid over-filling while still reacting quickly to conditions.
        bool continuousMode;
    }
}
