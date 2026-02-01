#!/bin/bash
#
# Start OpsSquad nodes on all containers (nodes must already be installed)
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
echo -e "${BLUE}Starting OpsSquad nodes...${NC}"
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

STARTED=0
ALREADY_RUNNING=0
FAILED=0

for CONTAINER in $CONTAINERS; do
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo -e "${YELLOW}⊘${NC} $CONTAINER: Container not running"
        continue
    fi

    # Check if node is already running
    if docker exec "$CONTAINER" pgrep -f opssquad-connectivity-layer > /dev/null 2>&1; then
        echo -e "${BLUE}●${NC} $CONTAINER: Node already running"
        ((ALREADY_RUNNING++))
        continue
    fi

    # Try to start node
    RESULT=$(docker exec "$CONTAINER" bash -c '
        NODE_BINARY="$HOME/.local/lib/opssquad/opssquad-connectivity-layer"
        NODE_CONFIG="$HOME/.config/opssquad/node.yaml"

        if [ ! -f "$NODE_BINARY" ]; then
            echo "NOT_INSTALLED"
            exit 1
        fi

        if [ ! -f "$NODE_CONFIG" ]; then
            echo "NO_CONFIG"
            exit 1
        fi

        nohup "$NODE_BINARY" --config "$NODE_CONFIG" > /var/log/opssquad-connectivity-layer.log 2>&1 &
        sleep 2

        if pgrep -f opssquad-connectivity-layer > /dev/null; then
            echo "STARTED"
        else
            echo "FAILED"
        fi
    ' 2>/dev/null)

    case "$RESULT" in
        STARTED)
            echo -e "${GREEN}✓${NC} $CONTAINER: Node started"
            ((STARTED++))
            ;;
        NOT_INSTALLED)
            echo -e "${RED}✗${NC} $CONTAINER: Node not installed"
            ((FAILED++))
            ;;
        NO_CONFIG)
            echo -e "${RED}✗${NC} $CONTAINER: Node config missing"
            ((FAILED++))
            ;;
        *)
            echo -e "${RED}✗${NC} $CONTAINER: Failed to start node"
            ((FAILED++))
            ;;
    esac
done

echo ""
echo -e "Done: ${GREEN}$STARTED started${NC}, ${BLUE}$ALREADY_RUNNING already running${NC}, ${RED}$FAILED failed${NC}"
echo ""
