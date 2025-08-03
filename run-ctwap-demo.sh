#!/bin/bash

# Simple CTWAP Order Executor with Retry Logic
# This version saves output to file for reliable parsing

# Load environment variables
source .env

# Configuration
TOTAL_CHUNKS=${TOTAL_CHUNKS:-2}
CHUNK_INTERVAL=${CHUNK_INTERVAL:-2}
RPC_URL=${RPC_URL:-"https://mainnet.base.org"}
MAX_RETRIES=${MAX_RETRIES:-10}
RETRY_DELAY=${RETRY_DELAY:-25}

echo "=== CTWAP Order Executor ==="
echo "Total chunks: $TOTAL_CHUNKS"
echo "Chunk interval: $CHUNK_INTERVAL seconds"
echo "Max retries per chunk: $MAX_RETRIES"
echo ""

# Step 1: Create and register the order
echo "Step 1: Creating CTWAP order..."
    
# Run forge script and save output to file
forge script script/deploy.s.sol:CreateCTWAPOrder \
    --rpc-url $RPC_URL \
    --broadcast \
    -vvv > order_output.txt 2>&1

# Check if script succeeded
if [ $? -ne 0 ]; then
    echo "Error: Order creation failed"
    cat order_output.txt
    exit 1
fi

# Extract order details from file - handling spaces after =
ORDER_HASH=$(cat order_output.txt | grep "ORDER_HASH=" | sed 's/.*ORDER_HASH=\s*//' | tr -d ' ' | tail -1)
ORDER_SALT=$(cat order_output.txt | grep "ORDER_SALT=" | sed 's/.*ORDER_SALT=\s*//' | tr -d ' ' | tail -1)
ORDER_R=$(cat order_output.txt | grep "ORDER_R=" | sed 's/.*ORDER_R=\s*//' | tr -d ' ' | tail -1)
ORDER_VS=$(cat order_output.txt | grep "ORDER_VS=" | sed 's/.*ORDER_VS=\s*//' | tr -d ' ' | tail -1)
MAKER_ADDRESS=$(cat order_output.txt | grep "MAKER_ADDRESS=" | sed 's/.*MAKER_ADDRESS=\s*//' | tr -d ' ' | tail -1)
MAKING_AMOUNT=$(cat order_output.txt | grep "MAKING_AMOUNT=" | sed 's/.*MAKING_AMOUNT=\s*//' | tr -d ' ' | tail -1)
TAKING_AMOUNT=$(cat order_output.txt | grep "TAKING_AMOUNT=" | sed 's/.*TAKING_AMOUNT=\s*//' | tr -d ' ' | tail -1)

echo "Order created successfully!"
echo "Order hash: $ORDER_HASH"

# Verify we got the order hash
if [ -z "$ORDER_HASH" ] || [ "$ORDER_HASH" = " " ]; then
    echo "Error: Could not extract order hash"
    echo "Check order_output.txt for details"
    exit 1
fi

# Save order details to env file
cat > .ctwap_order << EOF
ORDER_HASH=$ORDER_HASH
ORDER_SALT=$ORDER_SALT
ORDER_R=$ORDER_R
ORDER_VS=$ORDER_VS
MAKER_ADDRESS=$MAKER_ADDRESS
MAKING_AMOUNT=$MAKING_AMOUNT
TAKING_AMOUNT=$TAKING_AMOUNT
TOTAL_CHUNKS=$TOTAL_CHUNKS
EOF

echo "Order details saved to .ctwap_order"
echo ""

# Step 2: Execute chunks with retry logic
for ((i=1; i<=$TOTAL_CHUNKS; i++)); do
    echo "Executing chunk $i of $TOTAL_CHUNKS..."
    
    # Load order details and set chunk number
    source .ctwap_order
    export ORDER_HASH ORDER_SALT ORDER_R ORDER_VS MAKER_ADDRESS MAKING_AMOUNT TAKING_AMOUNT TOTAL_CHUNKS
    export CHUNK_NUMBER=$i
    
    # Retry logic for chunk execution
    retry_count=0
    chunk_executed=false
    
    while [ $retry_count -lt $MAX_RETRIES ] && [ "$chunk_executed" = false ]; do
        # Execute chunk and capture output
        forge script script/deploy.s.sol:ExecuteCTWAPChunk \
            --rpc-url $RPC_URL \
            --broadcast \
            -vvv > chunk_output.txt 2>&1
        
        # Check if chunk was executed successfully
        if grep -q "CHUNK_EXECUTED=true" chunk_output.txt; then
            echo "Chunk $i executed successfully!"
            chunk_executed=true
        elif grep -q "Too early for next chunk" chunk_output.txt; then
            retry_count=$((retry_count + 1))
            echo "Too early for next chunk. Retry $retry_count/$MAX_RETRIES in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        elif grep -q "All chunks executed" chunk_output.txt; then
            echo "All chunks already executed."
            chunk_executed=true
        elif grep -q "Order expired" chunk_output.txt; then
            echo "Error: Order has expired"
            cat chunk_output.txt
            exit 1
        else
            # Some other error occurred
            echo "Error executing chunk $i:"
            cat chunk_output.txt
            exit 1
        fi
    done
    
    if [ "$chunk_executed" = false ]; then
        echo "Failed to execute chunk $i after $MAX_RETRIES retries"
        exit 1
    fi
    
    # Wait before next chunk (except for last chunk)
    if [ $i -lt $TOTAL_CHUNKS ]; then
        echo "Waiting $CHUNK_INTERVAL seconds for next chunk..."
        sleep $CHUNK_INTERVAL
    fi
    
    echo ""
done

# Cleanup (comment out for debugging)
# rm -f order_output.txt chunk_output.txt .ctwap_order

echo "=== CTWAP execution complete! ==="