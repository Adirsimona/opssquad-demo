#!/bin/bash
#
# Check OpsSquad Node Status on all containers
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${1:-$DEMO_DIR/nodes.json}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║               OpsSquad Node Status Check                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required. Install with: brew install jq${NC}"
    exit 1
fi

# Define containers to check
if [ -f "$CONFIG_FILE" ]; then
    CONTAINERS=$(jq -r '.nodes[] | select(.enabled == true) | .container' "$CONFIG_FILE")
else
    # Fallback to hardcoded list
    CONTAINERS="fintech-api-gateway fintech-auth-service fintech-account-service fintech-transaction-service fintech-fraud-detection fintech-notification-service fintech-payment-processor"
fi

printf "%-30s %-15s %-10s %s\n" "Container" "Node Status" "PID" "Uptime"
echo "────────────────────────────────────────────────────────────────────────"

RUNNING=0
STOPPED=0
NOT_INSTALLED=0

for CONTAINER in $CONTAINERS; do
    # Check if container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        printf "%-30s ${YELLOW}%-15s${NC} %-10s %s\n" "$CONTAINER" "Container Down" "-" "-"
        continue
    fi

    # Check node status
    STATUS=$(docker exec "$CONTAINER" bash -c '
        if pgrep -f opssquad-connectivity-layer > /dev/null 2>&1; then
            PID=$(pgrep -f opssquad-connectivity-layer | head -1)
            # Get uptime (works on Linux)
            if [ -f "/proc/$PID/stat" ]; then
                START_TIME=$(stat -c %Y /proc/$PID 2>/dev/null || echo "0")
                NOW=$(date +%s)
                UPTIME=$((NOW - START_TIME))
                if [ $UPTIME -gt 3600 ]; then
                    UPTIME_STR="$((UPTIME / 3600))h $((UPTIME % 3600 / 60))m"
                elif [ $UPTIME -gt 60 ]; then
                    UPTIME_STR="$((UPTIME / 60))m $((UPTIME % 60))s"
                else
                    UPTIME_STR="${UPTIME}s"
                fi
            else
                UPTIME_STR="unknown"
            fi
            echo "RUNNING|$PID|$UPTIME_STR"
        elif [ -f "$HOME/.local/bin/opssquad" ]; then
            echo "STOPPED|-|-"
        else
            echo "NOT_INSTALLED|-|-"
        fi
    ' 2>/dev/null)

    STATE=$(echo "$STATUS" | cut -d'|' -f1)
    PID=$(echo "$STATUS" | cut -d'|' -f2)
    UPTIME=$(echo "$STATUS" | cut -d'|' -f3)

    case "$STATE" in
        RUNNING)
            printf "%-30s ${GREEN}%-15s${NC} %-10s %s\n" "$CONTAINER" "Running" "$PID" "$UPTIME"
            ((RUNNING++))
            ;;
        STOPPED)
            printf "%-30s ${YELLOW}%-15s${NC} %-10s %s\n" "$CONTAINER" "Stopped" "-" "-"
            ((STOPPED++))
            ;;
        NOT_INSTALLED)
            printf "%-30s ${RED}%-15s${NC} %-10s %s\n" "$CONTAINER" "Not Installed" "-" "-"
            ((NOT_INSTALLED++))
            ;;
        *)
            printf "%-30s ${RED}%-15s${NC} %-10s %s\n" "$CONTAINER" "Unknown" "-" "-"
            ;;
    esac
done

echo "────────────────────────────────────────────────────────────────────────"
echo ""
echo -e "Summary: ${GREEN}$RUNNING running${NC}, ${YELLOW}$STOPPED stopped${NC}, ${RED}$NOT_INSTALLED not installed${NC}"
echo ""

if [ $STOPPED -gt 0 ]; then
    echo "To start stopped nodes:"
    echo "  ./scripts/start-nodes.sh"
    echo ""
fi

if [ $NOT_INSTALLED -gt 0 ]; then
    echo "To install missing nodes:"
    echo "  ./scripts/install-nodes.sh"
    echo ""
fi
