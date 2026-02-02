#!/bin/bash
#
# Uninstall OpsSquad nodes from all containers
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
echo -e "${BLUE}Uninstalling OpsSquad nodes...${NC}"
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

UNINSTALLED=0
NOT_INSTALLED=0

for CONTAINER in $CONTAINERS; do
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        continue
    fi

    # Uninstall node using CLI
    RESULT=$(docker exec "$CONTAINER" bash -c '
        export PATH="$HOME/.local/bin:$PATH"

        # Check if CLI is installed
        if ! command -v opssquad &> /dev/null; then
            echo "NOT_INSTALLED"
            exit 0
        fi

        # Stop node if running
        opssquad node stop 2>/dev/null || true

        # Uninstall node
        opssquad node uninstall 2>/dev/null || true

        # Clean up CLI and remaining files
        rm -rf "$HOME/.local/bin/opssquad" 2>/dev/null
        rm -rf "$HOME/.local/lib/opssquad" 2>/dev/null
        rm -rf "$HOME/.config/opssquad" 2>/dev/null
        rm -f /var/log/opssquad-node.log 2>/dev/null

        echo "UNINSTALLED"
    ' 2>/dev/null)

    case "$RESULT" in
        UNINSTALLED)
            echo -e "${GREEN}✓${NC} $CONTAINER: Node uninstalled"
            ((UNINSTALLED++))
            ;;
        NOT_INSTALLED)
            echo -e "${YELLOW}●${NC} $CONTAINER: Node not installed"
            ((NOT_INSTALLED++))
            ;;
    esac
done

echo ""
echo -e "Done: ${GREEN}$UNINSTALLED uninstalled${NC}, ${YELLOW}$NOT_INSTALLED not installed${NC}"
echo ""
