#!/bin/bash
#
# Stop OpsSquad agents on all containers
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
echo -e "${BLUE}Stopping OpsSquad agents...${NC}"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required. Install with: brew install jq${NC}"
    exit 1
fi

# Get containers from config or use defaults
if [ -f "$CONFIG_FILE" ]; then
    CONTAINERS=$(jq -r '.nodes[] | select(.enabled == true) | .container' "$CONFIG_FILE")
else
    CONTAINERS="fintech-api-gateway fintech-auth-service fintech-account-service fintech-transaction-service fintech-fraud-detection fintech-notification-service fintech-payment-processor"
fi

STOPPED=0
NOT_RUNNING=0

for CONTAINER in $CONTAINERS; do
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        continue
    fi

    # Check if agent is running
    if docker exec "$CONTAINER" pgrep -f fixpanic-connectivity-layer > /dev/null 2>&1; then
        docker exec "$CONTAINER" pkill -f fixpanic-connectivity-layer 2>/dev/null
        echo -e "${GREEN}✓${NC} $CONTAINER: Agent stopped"
        ((STOPPED++))
    else
        echo -e "${YELLOW}●${NC} $CONTAINER: Agent not running"
        ((NOT_RUNNING++))
    fi
done

echo ""
echo -e "Done: ${GREEN}$STOPPED stopped${NC}, ${YELLOW}$NOT_RUNNING not running${NC}"
echo ""
