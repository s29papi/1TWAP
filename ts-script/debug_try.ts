import { ethers } from 'ethers';
import * as dotenv from 'dotenv';

dotenv.config();

// Contract addresses
const STRATEGY_ADDRESS = process.env.STRATEGY_ADDRESS!;

// ABIs
const CTWAP_STRATEGY_ABI = [
    'function authorizedResolvers(address resolver) view returns (bool)',
    'function setResolverAuthorization(address resolver, bool authorized)',
    'function owner() view returns (address)',
    'function paused() view returns (bool)',
    'function twapParams(bytes32 orderHash) view returns (tuple(bool initialized, uint256 totalChunks, uint256 chunkInterval, uint64 startTime, uint64 endTime, uint256 minChunkSize, uint256 maxPriceImpact))',
    'function ctwapParams(bytes32 orderHash) view returns (tuple(bool volatilityEnabled, uint256 minVolatility, uint256 maxVolatility, uint256 volatilityWindow, address priceOracle, address volatilityOracle, address sequencerOracle, uint256 maxPriceStaleness, bool adaptiveChunkSize, bool continuousMode, address makerAsset))'
];

async function debug() {
    const provider = new ethers.JsonRpcProvider(process.env.RPC_URL || 'https://mainnet.base.org');
    const signer = new ethers.Wallet(process.env.RESOLVER_KEY!, provider);
    const strategy = new ethers.Contract(STRATEGY_ADDRESS, CTWAP_STRATEGY_ABI, signer);
    
    console.log('=== CTWAP Strategy Debug Info ===\n');
    console.log('Strategy address:', STRATEGY_ADDRESS);
    console.log('Resolver address:', signer.address);
    
    try {
        // Check contract owner
        const owner = await strategy.owner();
        console.log('Contract owner:', owner);
        console.log('Is resolver the owner?', owner.toLowerCase() === signer.address.toLowerCase());
    } catch (e) {
        console.log('Could not get owner (method might not exist)');
    }
    
    try {
        // Check if paused
        const paused = await strategy.paused();
        console.log('Contract paused:', paused);
    } catch (e) {
        console.log('Could not check paused state (method might not exist)');
    }
    
    try {
        // Check resolver authorization
        const isAuthorized = await strategy.authorizedResolvers(signer.address);
        console.log('Resolver authorized:', isAuthorized);
        
        if (!isAuthorized) {
            console.log('\n⚠️  ISSUE FOUND: Resolver is not authorized!');
            console.log('Solution: The contract owner needs to call:');
            console.log(`strategy.setResolverAuthorization("${signer.address}", true)`);
        }
    } catch (e) {
        console.log('Could not check resolver authorization:', e);
    }
    
    // Test order hash
    const testOrderHash = '0x5ab5a84bd873cbed252d033c73006e7c7c8c86ff9c11cb3a24ee481996f39844';
    console.log('\nChecking if order already exists...');
    console.log('Order hash:', testOrderHash);
    
    try {
        const twapParams = await strategy.twapParams(testOrderHash);
        console.log('Order already registered:', twapParams.initialized);
        if (twapParams.initialized) {
            console.log('Total chunks:', twapParams.totalChunks.toString());
            console.log('Chunk interval:', twapParams.chunkInterval.toString());
        }
    } catch (e) {
        console.log('Could not check TWAP params:', e);
    }
}

debug().catch(console.error);