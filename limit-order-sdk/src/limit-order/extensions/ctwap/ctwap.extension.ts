// src/limit-order/extensions/ctwap/ctwap.extension.ts
import { ethers, Contract, Provider } from 'ethers'
import { ExtensionBuilder } from '../extension-builder.js'
import { Extension } from '../extension.js'
import { Address } from '../../../address.js'
import { Interaction } from '../../interaction.js'
import { BytesBuilder, BytesIter } from '@1inch/byte-utils'

/**
 * @title CTWAPExtension
 * @notice Extension for Conditional Time-Weighted Average Price orders
 */
export class CTWAPExtension {
    private constructor(
        public readonly address: Address,
        public readonly ctwapParams: CTWAPEncodedParams,
        public readonly contract?: Contract,
        public readonly makerPermit?: Interaction
    ) {}

    /**
     * Create new CTWAPExtension
     */
    static new(
        address: Address,
        ctwapParams: CTWAPEncodedParams,
        extra?: {
            makerPermit?: Interaction
            provider?: Provider
        }
    ): CTWAPExtension {
        let contract: Contract | undefined

        if (extra?.provider) {
            contract = new Contract(
                address.toString(),
                CTWAP_STRATEGY_ABI,
                extra.provider
            )
        }

        return new CTWAPExtension(
            address,
            ctwapParams,
            contract,
            extra?.makerPermit
        )
    }

    /**
     * Build Extension object for use in limit orders
     */
    build(): Extension {
        // CTWAP uses pre/post interactions
        const builder = new ExtensionBuilder()
            .withPreInteraction(new Interaction(this.address, '0x'))
            .withPostInteraction(new Interaction(this.address, '0x'))

        if (this.makerPermit) {
            builder.withMakerPermit(
                this.makerPermit.target,
                this.makerPermit.data
            )
        }

        // Store CTWAP params in custom data
        builder.withCustomData(this.encodeCTWAPParams())

        return builder.build()
    }

    /**
     * Encode CTWAP parameters for storage
     */
    private encodeCTWAPParams(): string {
        const builder = new BytesBuilder()
        
        // Start with a version byte for future compatibility
        builder.addUint8(1n) // version 1
        
        // Encode base TWAP params
        builder
            .addUint32(BigInt(this.ctwapParams.totalChunks))
            .addUint32(BigInt(this.ctwapParams.chunkInterval))
            // For timestamps, we'll use two uint32s to represent a uint64
            .addUint32(BigInt(Math.floor(this.ctwapParams.startTime / 2**32)))  // high 32 bits
            .addUint32(BigInt(this.ctwapParams.startTime % 2**32))              // low 32 bits
            .addUint32(BigInt(Math.floor(this.ctwapParams.endTime / 2**32)))    // high 32 bits
            .addUint32(BigInt(this.ctwapParams.endTime % 2**32))                // low 32 bits
            .addUint256(this.ctwapParams.minChunkSize)
            .addUint16(BigInt(this.ctwapParams.maxPriceImpact))
        
        // Encode volatility params
        builder
            .addUint8(this.ctwapParams.volatilityEnabled ? 1n : 0n)
            .addUint16(BigInt(this.ctwapParams.minVolatility || 0))
            .addUint16(BigInt(this.ctwapParams.maxVolatility || 0))
            .addUint8(BigInt(this.ctwapParams.volatilityWindow || 0))
        
        // Encode oracle addresses
        builder
            .addAddress(this.ctwapParams.priceOracle?.toString() || Address.ZERO_ADDRESS.toString())
            .addAddress(this.ctwapParams.volatilityOracle?.toString() || Address.ZERO_ADDRESS.toString())
            .addAddress(this.ctwapParams.sequencerOracle?.toString() || Address.ZERO_ADDRESS.toString())
        
        // Encode additional params
        builder
            .addUint32(BigInt(this.ctwapParams.maxPriceStaleness || 0))
            .addUint8(this.ctwapParams.adaptiveChunkSize ? 1n : 0n)
            .addUint8(this.ctwapParams.continuousMode ? 1n : 0n)

        return builder.asHex()
    }

    /**
     * Create from existing Extension (for deserialization)
     */
    static fromExtension(extension: Extension, expectedContract: Address): CTWAPExtension {
        const preInteraction = Interaction.decode(extension.preInteraction)
        const postInteraction = Interaction.decode(extension.postInteraction)
        
        if (!preInteraction.target.equal(expectedContract) || !postInteraction.target.equal(expectedContract)) {
            throw new Error('Extension contract address does not match expected CTWAP strategy address')
        }

        // Decode CTWAP params from custom data
        const params = CTWAPExtension.decodeCTWAPParams(extension.customData)

        const permit = extension.hasMakerPermit
            ? Interaction.decode(extension.makerPermit)
            : undefined

        return new CTWAPExtension(
            expectedContract,
            params,
            undefined, // contract not available in deserialization
            permit
        )
    }

    /**
     * Decode CTWAP parameters from bytes
     * @public Made public for use by LimitOrderWithCTWAP
     */
    public static decodeCTWAPParams(data: string): CTWAPEncodedParams {
        const iter = BytesIter.HexString(data)
        
        // Read version byte
        const version = iter.nextUint8()
        if (version !== '0x01') {
            throw new Error(`Unsupported CTWAP params version: ${version}`)
        }
        
        // Read base TWAP params
        const totalChunks = Number(iter.nextUint32())
        const chunkInterval = Number(iter.nextUint32())
        
        // Read timestamps as two uint32s each
        const startTimeHigh = BigInt(iter.nextUint32())
        const startTimeLow = BigInt(iter.nextUint32())
        const startTime = Number((startTimeHigh << 32n) | startTimeLow)
        
        const endTimeHigh = BigInt(iter.nextUint32())
        const endTimeLow = BigInt(iter.nextUint32())
        const endTime = Number((endTimeHigh << 32n) | endTimeLow)
        
        const minChunkSize = BigInt(iter.nextUint256())
        const maxPriceImpact = Number(iter.nextUint16())
        
        return {
            // Base TWAP params
            totalChunks,
            chunkInterval,
            startTime,
            endTime,
            minChunkSize,
            maxPriceImpact,
            
            // Volatility params
            volatilityEnabled: iter.nextUint8() === '0x01',
            minVolatility: Number(iter.nextUint16()),
            maxVolatility: Number(iter.nextUint16()),
            volatilityWindow: Number(iter.nextUint8()),
            
            // Oracle addresses
            priceOracle: new Address(iter.nextUint160()),
            volatilityOracle: new Address(iter.nextUint160()),
            sequencerOracle: new Address(iter.nextUint160()),
            
            // Additional params
            maxPriceStaleness: Number(iter.nextUint32()),
            adaptiveChunkSize: iter.nextUint8() === '0x01',
            continuousMode: iter.nextUint8() === '0x01'
        }
    }

    /**
     * Preview execution schedule
     */
    async previewExecutionSchedule(
        totalAmount: bigint,
        currentTime?: number
    ): Promise<ExecutionSchedule[]> {
        const now = currentTime || Math.floor(Date.now() / 1000)
        const schedule: ExecutionSchedule[] = []
        
        const chunkSize = totalAmount / BigInt(this.ctwapParams.totalChunks)
        const remainder = totalAmount % BigInt(this.ctwapParams.totalChunks)
        
        for (let i = 0; i < this.ctwapParams.totalChunks; i++) {
            const executionTime = this.ctwapParams.startTime + (i * this.ctwapParams.chunkInterval)
            const amount = i === this.ctwapParams.totalChunks - 1 
                ? chunkSize + remainder 
                : chunkSize
            
            schedule.push({
                chunkNumber: i + 1,
                executionTime,
                amount,
                status: now >= executionTime ? 'executable' : 'pending',
                estimatedVolatility: this.ctwapParams.volatilityEnabled ? await this.estimateVolatility() : undefined
            })
        }
        
        return schedule
    }

    /**
     * Estimate volatility (placeholder - would integrate with oracle)
     */
    private async estimateVolatility(): Promise<number> {
        // In production, this would query the volatility oracle
        return 5000 // 50% placeholder
    }

    /**
     * Get human-readable extension information
     */
    getInfo(): string {
        const chunks = this.ctwapParams.totalChunks
        const duration = (this.ctwapParams.endTime - this.ctwapParams.startTime) / 60
        
        let info = `CTWAP(${this.address.toString().slice(0, 8)}...) `
        info += `${chunks} chunks over ${duration} minutes `
        
        if (this.ctwapParams.volatilityEnabled) {
            info += `Vol: ${this.ctwapParams.minVolatility / 100}%-${this.ctwapParams.maxVolatility / 100}% `
        }
        
        if (this.ctwapParams.continuousMode) {
            info += `[Continuous] `
        }
        
        if (this.ctwapParams.adaptiveChunkSize) {
            info += `[Adaptive] `
        }
        
        return info
    }
}

// Parameter structure matching the contract
export interface CTWAPEncodedParams {
    // Base TWAP params
    totalChunks: number
    chunkInterval: number
    startTime: number
    endTime: number
    minChunkSize: bigint
    maxPriceImpact: number
    
    // Volatility params
    volatilityEnabled: boolean
    minVolatility: number
    maxVolatility: number
    volatilityWindow: number
    
    // Oracle addresses
    priceOracle?: Address
    volatilityOracle?: Address
    sequencerOracle?: Address
    
    // Additional params
    maxPriceStaleness: number
    adaptiveChunkSize: boolean
    continuousMode: boolean
}

export interface ExecutionSchedule {
    chunkNumber: number
    executionTime: number
    amount: bigint
    status: 'pending' | 'executable' | 'executed'
    estimatedVolatility?: number
}

// Helper for creating CTWAP parameters
export class CTWAPParamsBuilder {
    private params: Partial<CTWAPEncodedParams> = {
        totalChunks: 1,
        chunkInterval: 300, // 5 minutes default
        maxPriceImpact: 500, // 5% default
        volatilityEnabled: false,
        adaptiveChunkSize: false,
        continuousMode: false,
        maxPriceStaleness: 3600 // 1 hour default
    }

    static forBasicTWAP(chunks: number, durationMinutes: number): CTWAPParamsBuilder {
        const builder = new CTWAPParamsBuilder()
        const now = Math.floor(Date.now() / 1000)
        
        return builder
            .withChunks(chunks)
            .withTimeWindow(now, now + (durationMinutes * 60))
            .withChunkInterval(Math.floor((durationMinutes * 60) / chunks))
    }

    static forVolatilityTWAP(
        chunks: number, 
        durationMinutes: number,
        minVol: number,
        maxVol: number
    ): CTWAPParamsBuilder {
        return CTWAPParamsBuilder.forBasicTWAP(chunks, durationMinutes)
            .withVolatilityBounds(minVol, maxVol)
            .withAdaptiveChunkSize(true)
    }

    withChunks(chunks: number): this {
        this.params.totalChunks = chunks
        return this
    }

    withChunkInterval(seconds: number): this {
        this.params.chunkInterval = seconds
        return this
    }

    withTimeWindow(startTime: number, endTime: number): this {
        this.params.startTime = startTime
        this.params.endTime = endTime
        return this
    }

    withMinChunkSize(size: bigint): this {
        this.params.minChunkSize = size
        return this
    }

    withMaxPriceImpact(bps: number): this {
        this.params.maxPriceImpact = bps
        return this
    }

    withVolatilityBounds(minBps: number, maxBps: number): this {
        this.params.volatilityEnabled = true
        this.params.minVolatility = minBps
        this.params.maxVolatility = maxBps
        return this
    }

    withPriceOracle(oracle: Address): this {
        this.params.priceOracle = oracle
        return this
    }

    withVolatilityOracle(oracle: Address): this {
        this.params.volatilityOracle = oracle
        return this
    }

    withSequencerOracle(oracle: Address): this {
        this.params.sequencerOracle = oracle
        return this
    }

    withAdaptiveChunkSize(enabled: boolean): this {
        this.params.adaptiveChunkSize = enabled
        return this
    }

    withContinuousMode(enabled: boolean): this {
        this.params.continuousMode = enabled
        return this
    }

    build(): CTWAPEncodedParams {
        // Validate required fields
        if (!this.params.startTime || !this.params.endTime) {
            throw new Error('Start and end times are required')
        }
        
        if (!this.params.minChunkSize) {
            throw new Error('Minimum chunk size is required')
        }
        
        if (this.params.volatilityEnabled && (!this.params.minVolatility || !this.params.maxVolatility)) {
            throw new Error('Volatility bounds required when volatility is enabled')
        }
        
        return this.params as CTWAPEncodedParams
    }
}

const CTWAP_STRATEGY_ABI = [
    // Minimal ABI for strategy interactions
    {
        "inputs": [
            {"internalType": "bytes32", "name": "orderHash", "type": "bytes32"},
            {"components": [/* CTWAPParams struct */], "name": "params", "type": "tuple"}
        ],
        "name": "registerCTWAPOrder",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
]