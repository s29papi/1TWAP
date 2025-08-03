// src/limit-order/limit-order-with-ctwap.ts
import { UINT_40_MAX } from '@1inch/byte-utils'
import { CTWAPExtension } from './extensions/ctwap/ctwap.extension.js'
import { LimitOrder } from './limit-order.js'
import { LimitOrderV4Struct, OrderInfoData } from './types.js'
import { MakerTraits } from './maker-traits.js'
import { Extension } from './extensions/extension.js'
import { Address } from '../address.js'
import { randBigInt } from '../utils/rand-bigint.js'
import { Provider, Contract } from 'ethers'

export interface CTWAPParams {
    baseParams: {
        totalChunks: number
        chunkInterval: number
        startTime: number
        endTime: number
        minChunkSize: bigint
        maxPriceImpact: number
    }
    volatilityEnabled: boolean
    minVolatility?: number
    maxVolatility?: number
    volatilityWindow?: number
    priceOracle?: Address
    volatilityOracle?: Address
    sequencerOracle?: Address
    maxPriceStaleness?: number
    adaptiveChunkSize?: boolean
    continuousMode?: boolean
}

export interface CTWAPState {
    executedChunks: number
    lastExecutionTime: number
    totalMakingAmount: bigint
    totalTakingAmount: bigint
    currentVolatility?: number
}

/**
 * @title LimitOrderWithCTWAP
 * @notice Limit order with Conditional TWAP (Time-Weighted Average Price) strategy
 */
export class LimitOrderWithCTWAP extends LimitOrder {
    constructor(
        orderInfo: OrderInfoData,
        makerTraits = MakerTraits.default(),
        public readonly ctwapExtension: CTWAPExtension,
        public readonly ctwapParams: CTWAPParams
    ) {
        // Enable pre and post interactions for CTWAP
        makerTraits
            .enablePreInteraction()
            .enablePostInteraction()
            .allowMultipleFills() // Required for TWAP chunks
            .allowPartialFills()  // Required for chunk execution

        super(
            orderInfo,
            makerTraits,
            ctwapExtension.build()
        )
    }

    /**
     * Create a new CTWAP order with random nonce
     */
    static withRandomNonce(
        orderInfo: OrderInfoData,
        ctwapExtension: CTWAPExtension,
        ctwapParams: CTWAPParams,
        makerTraits = MakerTraits.default()
    ): LimitOrderWithCTWAP {
        makerTraits.withNonce(randBigInt(UINT_40_MAX))
        
        return new LimitOrderWithCTWAP(
            orderInfo,
            makerTraits,
            ctwapExtension,
            ctwapParams
        )
    }

    /**
     * Create from existing order data and extension
     * @override Maintains base class signature
     */
    static fromDataAndExtension(
        data: LimitOrderV4Struct,
        extension: Extension
    ): LimitOrderWithCTWAP {
        const makerTraits = new MakerTraits(BigInt(data.makerTraits))
        
        // Extract CTWAP extension and decode parameters from it
        const ctwapExt = CTWAPExtension.fromExtension(
            extension,
            new Address(data.receiver)
        )
        
        // Decode CTWAP params from extension's custom data
        const ctwapParams = this.decodeCTWAPParamsFromExtension(extension)

        return new LimitOrderWithCTWAP(
            {
                salt: BigInt(data.salt),
                maker: new Address(data.maker),
                makerAsset: new Address(data.makerAsset),
                takerAsset: new Address(data.takerAsset),
                makingAmount: BigInt(data.makingAmount),
                takingAmount: BigInt(data.takingAmount),
                receiver: new Address(data.receiver)
            },
            makerTraits,
            ctwapExt,
            ctwapParams
        )
    }

    /**
     * Create from data with explicit CTWAP params
     * Use this when you have the params separately
     */
    static fromDataAndParams(
        data: LimitOrderV4Struct,
        extension: Extension,
        ctwapParams: CTWAPParams
    ): LimitOrderWithCTWAP {
        const makerTraits = new MakerTraits(BigInt(data.makerTraits))
        const ctwapExt = CTWAPExtension.fromExtension(
            extension,
            new Address(data.receiver)
        )

        return new LimitOrderWithCTWAP(
            {
                salt: BigInt(data.salt),
                maker: new Address(data.maker),
                makerAsset: new Address(data.makerAsset),
                takerAsset: new Address(data.takerAsset),
                makingAmount: BigInt(data.makingAmount),
                takingAmount: BigInt(data.takingAmount),
                receiver: new Address(data.receiver)
            },
            makerTraits,
            ctwapExt,
            ctwapParams
        )
    }

    /**
     * Helper method to decode CTWAP params from extension
     */
    public static decodeCTWAPParamsFromExtension(extension: Extension): CTWAPParams {
        // Import the decoder from CTWAPExtension
        const encodedParams = CTWAPExtension.decodeCTWAPParams(extension.customData)
        
        // Convert encoded params to CTWAPParams format
        return {
            baseParams: {
                totalChunks: encodedParams.totalChunks,
                chunkInterval: encodedParams.chunkInterval,
                startTime: encodedParams.startTime,
                endTime: encodedParams.endTime,
                minChunkSize: encodedParams.minChunkSize,
                maxPriceImpact: encodedParams.maxPriceImpact
            },
            volatilityEnabled: encodedParams.volatilityEnabled,
            minVolatility: encodedParams.minVolatility,
            maxVolatility: encodedParams.maxVolatility,
            volatilityWindow: encodedParams.volatilityWindow,
            priceOracle: encodedParams.priceOracle,
            volatilityOracle: encodedParams.volatilityOracle,
            sequencerOracle: encodedParams.sequencerOracle,
            maxPriceStaleness: encodedParams.maxPriceStaleness,
            adaptiveChunkSize: encodedParams.adaptiveChunkSize,
            continuousMode: encodedParams.continuousMode
        }
    }

    /**
     * Get the current chunk size based on TWAP parameters and volatility
     */
    public getChunkSize(): bigint {
        const baseChunkSize = this.makingAmount / BigInt(this.ctwapParams.baseParams.totalChunks)
        
        if (!this.ctwapParams.volatilityEnabled || !this.ctwapParams.adaptiveChunkSize) {
            return baseChunkSize
        }

        // Adaptive sizing would be calculated based on current volatility
        // This is a simplified version - actual implementation would query the contract
        return baseChunkSize
    }

    /**
     * Calculate the expected execution schedule
     */
    public getExecutionSchedule(): Array<{ chunkNumber: number; timestamp: number; amount: bigint }> {
        const schedule: Array<{ chunkNumber: number; timestamp: number; amount: bigint }> = []
        const chunkSize = this.getChunkSize()
        const { totalChunks, chunkInterval, startTime } = this.ctwapParams.baseParams

        for (let i = 0; i < totalChunks; i++) {
            schedule.push({
                chunkNumber: i + 1,
                timestamp: startTime + (i * chunkInterval),
                amount: i === totalChunks - 1 
                    ? this.makingAmount - (chunkSize * BigInt(totalChunks - 1)) // Last chunk gets remainder
                    : chunkSize
            })
        }

        return schedule
    }

    /**
     * Check if order can be executed based on current conditions
     */
    public async canExecuteNextChunk(
        provider: Provider,
        ctwapStrategyAddress: string,
        currentState?: CTWAPState
    ): Promise<{ canExecute: boolean; reason: string }> {
        const contract = new Contract(
            ctwapStrategyAddress,
            CTWAP_STRATEGY_ABI,
            provider
        )

        const orderHash = this.getOrderHash(await provider.getNetwork().then(n => Number(n.chainId)))

        try {
            const [canExecute, reason] = await contract.canExecuteVolatilityChunk(orderHash)
            return { canExecute, reason }
        } catch (error) {
            return { canExecute: false, reason: 'Failed to check execution conditions' }
        }
    }

    /**
     * Get current volatility for the order
     */
    public async getCurrentVolatility(
        provider: Provider,
        ctwapStrategyAddress: string
    ): Promise<number> {
        if (!this.ctwapParams.volatilityEnabled) {
            return 0
        }

        const contract = new Contract(
            ctwapStrategyAddress,
            CTWAP_STRATEGY_ABI,
            provider
        )

        const orderHash = this.getOrderHash(await provider.getNetwork().then(n => Number(n.chainId)))

        try {
            const volatility = await contract.getCurrentVolatility(orderHash)
            return Number(volatility)
        } catch (error) {
            console.warn('Failed to get current volatility:', error)
            return 0
        }
    }

    /**
     * Get the next execution time for the order
     */
    public async getNextExecutionTime(
        provider: Provider,
        ctwapStrategyAddress: string
    ): Promise<number> {
        const contract = new Contract(
            ctwapStrategyAddress,
            CTWAP_STRATEGY_ABI,
            provider
        )

        const orderHash = this.getOrderHash(await provider.getNetwork().then(n => Number(n.chainId)))

        try {
            const nextTime = await contract.getNextExecutionTime(orderHash)
            return Number(nextTime)
        } catch (error) {
            console.warn('Failed to get next execution time:', error)
            return 0
        }
    }

    /**
     * Get TWAP parameters info
     */
    public getCTWAPInfo(): string {
        const { baseParams, volatilityEnabled } = this.ctwapParams
        
        let info = `CTWAP Order: ${baseParams.totalChunks} chunks over ${
            (baseParams.endTime - baseParams.startTime) / 60
        } minutes`
        
        if (volatilityEnabled) {
            info += ` | Volatility bounds: ${this.ctwapParams.minVolatility}-${this.ctwapParams.maxVolatility} bps`
        }
        
        return info
    }

    /**
     * Estimate gas for chunk execution
     */
    public async estimateChunkGas(
        provider: Provider,
        protocolAddress: string,
        taker: string,
        chunkSize: bigint
    ): Promise<bigint> {
        // This would call the protocol's estimateGas function
        // Simplified version:
        return BigInt(300000) // Typical gas for a chunk execution
    }
}

// Minimal ABI for CTWAP Strategy contract interactions
const CTWAP_STRATEGY_ABI = [
    {
        "inputs": [{"internalType": "bytes32", "name": "orderHash", "type": "bytes32"}],
        "name": "canExecuteVolatilityChunk",
        "outputs": [
            {"internalType": "bool", "name": "", "type": "bool"},
            {"internalType": "string", "name": "reason", "type": "string"}
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "bytes32", "name": "orderHash", "type": "bytes32"}],
        "name": "getCurrentVolatility",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "bytes32", "name": "orderHash", "type": "bytes32"}],
        "name": "getNextExecutionTime",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    }
]