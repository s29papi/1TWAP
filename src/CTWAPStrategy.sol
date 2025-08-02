// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "./interface/iTypes.sol";

// contract cTWAPStrategy is ReentrancyGuard, Ownable, IPreInteraction, IPostInteraction, iTypes {}
contract CTWAPStrategy is iTypes, Ownable {
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
}
