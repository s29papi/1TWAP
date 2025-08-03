import { ethers } from 'ethers';
import * as dotenv from 'dotenv';

dotenv.config();

// Constants
const HAS_EXTENSION_FLAG = BigInt(1) << BigInt(249);
const ALLOW_MULTIPLE_FILLS_FLAG = BigInt(1) << BigInt(254);
const PRE_INTERACTION_CALL_FLAG = BigInt(1) << BigInt(252);
const POST_INTERACTION_CALL_FLAG = BigInt(1) << BigInt(251);

// Base Mainnet addresses
const ONE_LOP = '0x111111125421cA6dc452d289314280a0f8842A65';
const WETH = '0x4200000000000000000000000000000000000006';
const USDC = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const ETH_USD_ORACLE = '0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70';
const SEQUENCER_UPTIME_FEED = '0xBCF85224fc0756B9Fa45aA7892530B47e10b6433';

// ABIs
const ERC20_ABI = [
    'function balanceOf(address owner) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function allowance(address owner, address spender) view returns (uint256)'
];

const ONE_INCH_ABI = [
    'function hashOrder(tuple(uint256 salt, uint256 maker, uint256 receiver, uint256 makerAsset, uint256 takerAsset, uint256 makingAmount, uint256 takingAmount, uint256 makerTraits) order) view returns (bytes32)',
    'function fillOrderArgs(tuple(uint256 salt, uint256 maker, uint256 receiver, uint256 makerAsset, uint256 takerAsset, uint256 makingAmount, uint256 takingAmount, uint256 makerTraits) order, bytes32 r, bytes32 vs, uint256 amount, uint256 takerTraits, bytes extension) returns (uint256 actualMaking, uint256 actualTaking, bytes32 orderHash)'
];

const CTWAP_STRATEGY_ABI = [
    'function registerCTWAPOrder(bytes32 orderHash, tuple(tuple(bool initialized, uint256 totalChunks, uint256 chunkInterval, uint64 startTime, uint64 endTime, uint256 minChunkSize, uint256 maxPriceImpact) baseParams, bool volatilityEnabled, uint256 minVolatility, uint256 maxVolatility, uint256 volatilityWindow, address priceOracle, address volatilityOracle, address sequencerOracle, uint256 maxPriceStaleness, bool adaptiveChunkSize, bool continuousMode, address makerAsset) params)',
    'function canExecuteVolatilityChunk(bytes32 orderHash) view returns (bool canExecute, string reason)',
    'function getCurrentVolatility(bytes32 orderHash) view returns (uint256)',
    'function twapStates(bytes32 orderHash) view returns (uint256 executedChunks, uint256 lastExecutionTime, uint256 totalMakingAmount, uint256 totalTakingAmount)',
    'function setResolverAuthorization(address resolver, bool authorized)',
    'function resolverAuthorization(address resolver) view returns (bool)',
    'function authorizedResolvers(address resolver) view returns (bool)',
    'function owner() view returns (address)'
];

const WETH_ABI = [
    ...ERC20_ABI,
    'receive() payable',
    'function deposit() payable'
];

interface Order {
    salt: bigint;
    maker: bigint;
    receiver: bigint;
    makerAsset: bigint;
    takerAsset: bigint;
    makingAmount: bigint;
    takingAmount: bigint;
    makerTraits: bigint;
}

interface CTWAPParams {
    baseParams: {
        initialized: boolean;
        totalChunks: number;
        chunkInterval: number;
        startTime: number;
        endTime: number;
        minChunkSize: bigint;
        maxPriceImpact: number;
    };
    volatilityEnabled: boolean;
    minVolatility: number;
    maxVolatility: number;
    volatilityWindow: number;
    priceOracle: string;
    volatilityOracle: string;
    sequencerOracle: string;
    maxPriceStaleness: number;
    adaptiveChunkSize: boolean;
    continuousMode: boolean;
    makerAsset: string;
}

class CTWAPExecutor {
    private provider: ethers.Provider;
    private signer: ethers.Wallet;
    private ctwapStrategy: ethers.Contract;
    private oneLOP: ethers.Contract;
    private usdc: ethers.Contract;
    private weth: ethers.Contract;
    private orderHash?: string;
    private resolverInterval?: NodeJS.Timeout;

    constructor() {
        const rpcUrl = process.env.RPC_URL || 'https://mainnet.base.org';
        this.provider = new ethers.JsonRpcProvider(rpcUrl);
        
        const privateKey = process.env.RESOLVER_KEY;
        if (!privateKey) throw new Error('RESOLVER_KEY not found in .env');
        
        this.signer = new ethers.Wallet(privateKey, this.provider);
        
        const strategyAddress = process.env.STRATEGY_ADDRESS;
        if (!strategyAddress) throw new Error('STRATEGY_ADDRESS not found in .env');
        
        this.ctwapStrategy = new ethers.Contract(strategyAddress, CTWAP_STRATEGY_ABI, this.signer);
        this.oneLOP = new ethers.Contract(ONE_LOP, ONE_INCH_ABI, this.signer);
        this.usdc = new ethers.Contract(USDC, ERC20_ABI, this.signer);
        this.weth = new ethers.Contract(WETH, WETH_ABI, this.signer);
    }

    async initialize() {
        console.log('Initializing CTWAP Executor...');
        console.log('Resolver address:', this.signer.address);
        console.log('Strategy address:', await this.ctwapStrategy.getAddress());
        
        const ethBalance = await this.provider.getBalance(this.signer.address);
        console.log('ETH balance:', ethers.formatEther(ethBalance), 'ETH');
        
        const usdcBalance = await this.usdc.balanceOf(this.signer.address);
        console.log('USDC balance:', ethers.formatUnits(usdcBalance, 6), 'USDC');
        
        // Check if resolver is authorized
        try {
            console.log('Checking resolver authorization...');
            // The contract uses authorizedResolvers mapping
            const isAuthorized = await this.ctwapStrategy.authorizedResolvers(this.signer.address);
            console.log('Resolver authorized:', isAuthorized);
            
            // Also check if we're the owner
            const owner = await this.ctwapStrategy.owner();
            console.log('Contract owner:', owner);
            const isOwner = owner.toLowerCase() === this.signer.address.toLowerCase();
            console.log('Is resolver the owner?', isOwner);
            
            if (!isAuthorized && !isOwner) {
                console.log('\n⚠️  WARNING: This address is not authorized as a resolver!');
                console.log('The contract owner needs to call setResolverAuthorization() for this address.');
                
                if (isOwner) {
                    console.log('You are the owner, attempting to authorize self...');
                    try {
                        const tx = await this.ctwapStrategy.setResolverAuthorization(this.signer.address, true);
                        await tx.wait();
                        console.log('Successfully authorized as resolver');
                    } catch (e) {
                        console.log('Failed to authorize:', e);
                    }
                }
            }
        } catch (e) {
            console.log('Could not check resolver authorization:', e);
        }
        
        // Check if we need to approve USDC
        const usdcAllowance = await this.usdc.allowance(this.signer.address, ONE_LOP);
        if (usdcAllowance < ethers.parseUnits('1000', 6)) {
            console.log('Approving USDC for 1inch...');
            const tx = await this.usdc.approve(ONE_LOP, ethers.MaxUint256);
            await tx.wait();
            console.log('USDC approved');
        }
        
        // Check if we need to approve WETH
        const wethAllowance = await this.weth.allowance(this.signer.address, ONE_LOP);
        if (wethAllowance < ethers.parseEther('1')) {
            console.log('Approving WETH for 1inch...');
            const tx = await this.weth.approve(ONE_LOP, ethers.MaxUint256);
            await tx.wait();
            console.log('WETH approved');
        }
    }

    async createOrder() {
        console.log('\n=== Creating CTWAP Order ===');
        
        const makingAmount = ethers.parseUnits('2', 6); // 2 USDC like in the working script
        const takingAmount = BigInt('582392541595494'); // Exact amount from working script
        
        // Build extension
        const extension = this.buildPrePostExtension(await this.ctwapStrategy.getAddress());
        const extHash160 = BigInt(ethers.keccak256(extension)) & ((BigInt(1) << BigInt(160)) - BigInt(1));
        const salt = (BigInt(Math.floor(Date.now() / 1000)) << BigInt(160)) | extHash160;
        
        // Create order
        const order: Order = {
            salt: salt,
            maker: BigInt(this.signer.address),
            receiver: BigInt(this.signer.address),
            makerAsset: BigInt(USDC),
            takerAsset: BigInt(WETH),
            makingAmount: makingAmount,
            takingAmount: takingAmount,
            makerTraits: this.makerTraitsWithExtension()
        };
        
        // Get order hash
        this.orderHash = await this.oneLOP.hashOrder(order);
        console.log('Order hash:', this.orderHash);
        
        // Sign order
        const { r, vs } = await this.signOrder(this.orderHash);
        
        // Register CTWAP parameters - matching the working Solidity script
        const currentTime = Math.floor(Date.now() / 1000);
        const params: CTWAPParams = {
            baseParams: {
                initialized: false,
                totalChunks: 1, // Single chunk like in the working script
                chunkInterval: 300, // 300 seconds like in the working script
                startTime: currentTime,
                endTime: currentTime + 3600, // 1 hour window
                minChunkSize: makingAmount / 2n, // Half of making amount
                maxPriceImpact: 2000 // 20% tolerance
            },
            volatilityEnabled: true,
            minVolatility: 100,    // 1% min
            maxVolatility: 50000,  // 500% max (very wide range)
            volatilityWindow: 3600,
            priceOracle: ETH_USD_ORACLE,
            volatilityOracle: ethers.ZeroAddress,
            sequencerOracle: SEQUENCER_UPTIME_FEED,
            maxPriceStaleness: 3600,
            adaptiveChunkSize: false,
            continuousMode: false,
            makerAsset: USDC
        };
        
        console.log('Registering CTWAP order...');
        console.log('Order details:');
        console.log('  Total chunks:', params.baseParams.totalChunks);
        console.log('  Chunk interval:', params.baseParams.chunkInterval, 'seconds');
        console.log('  Min chunk size:', ethers.formatUnits(params.baseParams.minChunkSize, 6), 'USDC');
        console.log('  Making amount:', ethers.formatUnits(makingAmount, 6), 'USDC');
        console.log('  Taking amount:', ethers.formatEther(takingAmount), 'ETH');
        
        try {
            // First try to estimate gas to get better error messages
            const gasEstimate = await this.ctwapStrategy.registerCTWAPOrder.estimateGas(this.orderHash, params);
            console.log('Gas estimate:', gasEstimate.toString());
            
            const tx = await this.ctwapStrategy.registerCTWAPOrder(this.orderHash, params, {
                gasLimit: gasEstimate * 120n / 100n // 20% buffer
            });
            await tx.wait();
            console.log('CTWAP order registered successfully');
        } catch (error: any) {
            console.error('Failed to register CTWAP order:');
            console.error('Error:', error.message);
            
            // Try to decode the error
            if (error.data) {
                console.error('Error data:', error.data);
            }
            
            // Common issues:
            console.log('\nPossible issues:');
            console.log('1. Resolver not authorized - check if your address is set as an authorized resolver');
            console.log('2. Order already registered - this order hash might already exist');
            console.log('3. Invalid parameters - check volatility ranges, time windows, etc.');
            console.log('4. Contract paused or disabled');
            
            throw error;
        }
        
        // Store order details for resolver
        return { order, r, vs, extension };
    }

    async startResolver(orderDetails: { order: Order; r: string; vs: string; extension: string }) {
        console.log('\n=== Starting Order Execution ===');
        
        // For single chunk execution, we just execute once
        try {
            // Check if can execute
            const [canExecute, reason] = await this.ctwapStrategy.canExecuteVolatilityChunk(this.orderHash);
            console.log('Can execute:', canExecute);
            
            if (!canExecute) {
                console.log('Reason:', reason);
                return;
            }
            
            // Get current volatility
            const volatility = await this.ctwapStrategy.getCurrentVolatility(this.orderHash);
            console.log('Current ETH volatility:', volatility.toString(), 'bps (', (Number(volatility) / 100).toFixed(2), '%)');
            
            // Ensure we have enough WETH
            const wethNeeded = orderDetails.order.takingAmount + ethers.parseEther('0.001'); // Extra for safety
            const wethBalance = await this.weth.balanceOf(this.signer.address);
            
            if (wethBalance < wethNeeded) {
                console.log('Wrapping ETH for order fill...');
                const wrapTx = await this.weth.deposit({ value: wethNeeded - wethBalance });
                await wrapTx.wait();
            }
            
            // Log balances before
            console.log('\nBefore fill:');
            const usdcBefore = await this.usdc.balanceOf(this.signer.address);
            const wethBefore = await this.weth.balanceOf(this.signer.address);
            console.log('  USDC:', ethers.formatUnits(usdcBefore, 6), 'USDC');
            console.log('  WETH:', ethers.formatUnits(wethBefore, 15), 'finney');
            
            // Fill the order
            console.log('\nFilling order...');
            const takerTraits = this.takerTraitsForExtension(orderDetails.extension);
            
            const fillTx = await this.oneLOP.fillOrderArgs(
                orderDetails.order,
                orderDetails.r,
                orderDetails.vs,
                orderDetails.order.makingAmount, // Full amount for single chunk
                takerTraits,
                orderDetails.extension
            );
            
            const receipt = await fillTx.wait();
            console.log('\nOrder filled successfully!');
            console.log('Transaction hash:', receipt.hash);
            console.log('Gas used:', receipt.gasUsed.toString());
            
            // Log balances after
            console.log('\nAfter fill:');
            const usdcAfter = await this.usdc.balanceOf(this.signer.address);
            const wethAfter = await this.weth.balanceOf(this.signer.address);
            console.log('  USDC:', ethers.formatUnits(usdcAfter, 6), 'USDC');
            console.log('  WETH:', ethers.formatUnits(wethAfter, 15), 'finney');
            
            // Get TWAP state
            const [executedChunks, lastTime, totalMaking, totalTaking] = 
                await this.ctwapStrategy.twapStates(this.orderHash);
            console.log('\nTWAP State:');
            console.log('  Executed chunks:', executedChunks.toString());
            console.log('  Total making:', ethers.formatUnits(totalMaking, 6), 'USDC');
            console.log('  Total taking:', ethers.formatUnits(totalTaking, 18), 'ETH');
            
        } catch (error: any) {
            console.error('Execution failed:', error.message);
            if (error.data) {
                console.error('Error data:', error.data);
            }
        }
    }

    stopResolver() {
        if (this.resolverInterval) {
            clearInterval(this.resolverInterval);
            console.log('Resolver stopped');
        }
    }

    private makerTraitsWithExtension(): bigint {
        return HAS_EXTENSION_FLAG | ALLOW_MULTIPLE_FILLS_FLAG | PRE_INTERACTION_CALL_FLAG | POST_INTERACTION_CALL_FLAG;
    }

    private takerTraitsForExtension(extension: string): bigint {
        const fillByMakingFlag = BigInt(1) << BigInt(255);
        const extensionBytes = ethers.getBytes(extension);
        const extensionLenBits = BigInt(extensionBytes.length) << BigInt(224);
        return fillByMakingFlag | extensionLenBits;
    }

    private async signOrder(orderHash: string): Promise<{ r: string; vs: string }> {
        // Sign the raw hash without message prefix to match Solidity vm.sign
        const msgHash = ethers.getBytes(orderHash);
        const signingKey = this.signer.signingKey;
        const signature = signingKey.sign(msgHash);
        
        // Convert v to vs format used by 1inch
        const v = signature.v;
        const adjustedV = v - 27; // Convert to 0 or 1
        const vs = (BigInt(adjustedV) << BigInt(255)) | BigInt(signature.s);
        
        return {
            r: signature.r,
            vs: '0x' + vs.toString(16).padStart(64, '0')
        };
    }

    private buildPrePostExtension(strategy: string): string {
        const pre = ethers.getBytes(strategy);
        const post = ethers.getBytes(strategy);
        
        const offsets = new Array(8).fill(0);
        let offset = 0;
        
        // First 6 offsets are 0
        for (let i = 0; i < 6; i++) {
            offsets[i] = offset;
        }
        
        // Pre interaction offset
        offset += pre.length;
        offsets[6] = offset;
        
        // Post interaction offset
        offset += post.length;
        offsets[7] = offset;
        
        // Pack offsets into uint256
        let packed = BigInt(0);
        for (let i = 0; i < 8; i++) {
            packed |= BigInt(offsets[i]) << BigInt(32 * i);
        }
        
        // Combine everything
        const packedBytes = ethers.toBeHex(packed, 32);
        const preHex = ethers.hexlify(pre);
        const postHex = ethers.hexlify(post);
        
        return packedBytes + preHex.slice(2) + postHex.slice(2);
    }
}

// Main execution
async function main() {
    const executor = new CTWAPExecutor();
    
    try {
        await executor.initialize();
        const orderDetails = await executor.createOrder();
        await executor.startResolver(orderDetails);
        
    } catch (error: any) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

main();