#!/bin/bash

DURATION="${1:-300}"  # Default 5 minutes
RATE="${2:-10}"       # Default 10 requests/second

API_URL="${API_URL:-http://localhost:8080}"

echo "========================================"
echo "  FinTech Traffic Generator"
echo "========================================"
echo ""
echo "Duration: ${DURATION}s"
echo "Rate: ${RATE} req/s"
echo "Target: ${API_URL}"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Sample account IDs from seed data
ACCOUNTS=(
    "aaaa1111-1111-1111-1111-111111111111"
    "aaaa2222-1111-1111-1111-111111111111"
    "bbbb1111-2222-2222-2222-222222222222"
    "cccc1111-3333-3333-3333-333333333333"
    "dddd1111-4444-4444-4444-444444444444"
)

START_TIME=$(date +%s)
REQUEST_COUNT=0
ERROR_COUNT=0

# Calculate sleep between requests
SLEEP_TIME=$(echo "scale=3; 1 / $RATE" | bc)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $DURATION ]; then
        break
    fi

    # Pick random action
    ACTION=$((RANDOM % 100))

    if [ $ACTION -lt 30 ]; then
        # 30% - Check balance (triggers memory leak if enabled)
        ACCOUNT="${ACCOUNTS[$((RANDOM % ${#ACCOUNTS[@]}))]}"
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/api/accounts/accounts/${ACCOUNT}/balance" 2>/dev/null)
        ENDPOINT="balance"
    elif [ $ACTION -lt 50 ]; then
        # 20% - Health check
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/api/accounts/health" 2>/dev/null)
        ENDPOINT="health"
    elif [ $ACTION -lt 70 ]; then
        # 20% - List accounts
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/api/accounts/accounts" 2>/dev/null)
        ENDPOINT="accounts"
    elif [ $ACTION -lt 85 ]; then
        # 15% - Token verification (triggers auth failures if enabled)
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/api/auth/verify" \
            -H "Content-Type: application/json" \
            -d '{"token":"test-token"}' 2>/dev/null)
        ENDPOINT="verify"
    else
        # 15% - Transfer (triggers cascade timeout if enabled)
        FROM="${ACCOUNTS[$((RANDOM % ${#ACCOUNTS[@]}))]}"
        TO="${ACCOUNTS[$((RANDOM % ${#ACCOUNTS[@]}))]}"
        AMOUNT=$((RANDOM % 1000 + 10))
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/api/transactions/transfer" \
            -H "Content-Type: application/json" \
            -d "{\"fromAccountId\":\"${FROM}\",\"toAccountId\":\"${TO}\",\"amount\":${AMOUNT}}" 2>/dev/null)
        ENDPOINT="transfer"
    fi

    REQUEST_COUNT=$((REQUEST_COUNT + 1))

    if [ "$RESPONSE" != "200" ] && [ "$RESPONSE" != "201" ]; then
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo "[${ELAPSED}s] ${ENDPOINT}: HTTP ${RESPONSE} (error)"
    else
        # Only show every 10th success to reduce noise
        if [ $((REQUEST_COUNT % 10)) -eq 0 ]; then
            ERROR_RATE=0
            if [ $REQUEST_COUNT -gt 0 ]; then
                ERROR_RATE=$(echo "scale=1; $ERROR_COUNT * 100 / $REQUEST_COUNT" | bc)
            fi
            echo "[${ELAPSED}s] Requests: ${REQUEST_COUNT}, Errors: ${ERROR_COUNT} (${ERROR_RATE}%)"
        fi
    fi

    sleep "$SLEEP_TIME"
done

echo ""
echo "========================================"
echo "  Traffic Generation Complete"
echo "========================================"
echo ""
echo "Total Requests: ${REQUEST_COUNT}"
echo "Total Errors: ${ERROR_COUNT}"
if [ $REQUEST_COUNT -gt 0 ]; then
    ERROR_RATE=$(echo "scale=2; $ERROR_COUNT * 100 / $REQUEST_COUNT" | bc)
    echo "Error Rate: ${ERROR_RATE}%"
fi
echo ""
