#!/bin/bash

API_URL="${API_URL:-http://localhost:8080}"

echo "========================================"
echo "  FinTech Demo Health Monitor"
echo "========================================"
echo ""
echo "Press Ctrl+C to stop"
echo ""

while true; do
    clear
    echo "========================================"
    echo "  FinTech Demo Health Status"
    echo "  $(date)"
    echo "========================================"
    echo ""

    # Check each service
    SERVICES=(
        "API Gateway:${API_URL}/health"
        "Auth Service:${API_URL}/api/auth/health"
        "Account Service:${API_URL}/api/accounts/health"
        "Transaction Service:${API_URL}/api/transactions/health"
        "Fraud Detection:${API_URL}/api/fraud/health"
        "Notification Service:${API_URL}/api/notifications/health"
        "Payment Processor:${API_URL}/api/payments/health"
    )

    printf "%-25s %-10s %-10s %s\n" "Service" "Status" "Latency" "Issues"
    printf "%-25s %-10s %-10s %s\n" "-------" "------" "-------" "------"

    for SERVICE_INFO in "${SERVICES[@]}"; do
        NAME="${SERVICE_INFO%%:*}"
        URL="${SERVICE_INFO#*:}"

        START=$(date +%s%N)
        RESPONSE=$(curl -s -w "\n%{http_code}" "$URL" 2>/dev/null)
        END=$(date +%s%N)

        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | sed '$d')
        LATENCY=$(( (END - START) / 1000000 ))

        if [ "$HTTP_CODE" == "200" ]; then
            STATUS="OK"
            COLOR="\033[32m"

            # Check for issues in response
            ISSUES=""
            if echo "$BODY" | grep -q '"memoryLeakEnabled":true\|"memoryLeakedMB":[1-9]'; then
                ISSUES="memory-leak"
            fi
            if echo "$BODY" | grep -q '"connectionLeakEnabled":true\|"leakedConnections":[1-9]'; then
                ISSUES="${ISSUES:+$ISSUES, }db-leak"
            fi
            if echo "$BODY" | grep -q '"slowConsumerEnabled":true'; then
                ISSUES="${ISSUES:+$ISSUES, }slow-consumer"
            fi
            if echo "$BODY" | grep -q '"tokenFailureEnabled":true'; then
                ISSUES="${ISSUES:+$ISSUES, }auth-failure"
            fi
            if echo "$BODY" | grep -q '"cascadeTimeoutEnabled":true'; then
                ISSUES="${ISSUES:+$ISSUES, }timeout"
            fi
            if echo "$BODY" | grep -q '"slowPaymentsEnabled":true\|"failuresEnabled":true'; then
                ISSUES="${ISSUES:+$ISSUES, }payment-slow"
            fi

            if [ $LATENCY -gt 2000 ]; then
                STATUS="SLOW"
                COLOR="\033[33m"
            fi
        else
            STATUS="DOWN"
            COLOR="\033[31m"
            ISSUES="unreachable"
        fi

        printf "${COLOR}%-25s %-10s %-10s %s\033[0m\n" "$NAME" "$STATUS" "${LATENCY}ms" "$ISSUES"
    done

    echo ""
    echo "========================================"
    echo ""

    # Docker stats
    echo "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep fintech || echo "No containers running"

    echo ""
    echo "Queue Stats (RabbitMQ):"
    curl -s -u fintech:fintech123 "http://localhost:15672/api/queues/%2F/notifications" 2>/dev/null | \
        jq -r '"  Messages: \(.messages), Consumers: \(.consumers)"' 2>/dev/null || echo "  Unable to fetch queue stats"

    echo ""
    sleep 5
done
