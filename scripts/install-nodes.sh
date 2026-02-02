#!/bin/bash
#
# OpsSquad Node Installation Script
# Reads nodes.json and installs OpsSquad nodes on all configured containers
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${1:-$DEMO_DIR/nodes.json}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            OpsSquad Node Installation Script               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
    echo ""
    echo "To get started:"
    echo "  1. Copy nodes.example.json to nodes.json"
    echo "  2. Fill in your node IDs and token from the OpsSquad dashboard"
    echo "  3. Run this script again"
    echo ""
    echo "Example:"
    echo "  cp nodes.example.json nodes.json"
    echo "  # Edit nodes.json with your credentials"
    echo "  ./scripts/install-nodes.sh"
    exit 1
fi

# Read global config
TOKEN=$(jq -r '.global.token' "$CONFIG_FILE")
SOCKET_URL=$(jq -r '.global.socket_url // "socket.opssquad.ai:9000"' "$CONFIG_FILE")

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ] || [ "$TOKEN" == "your-opssquad-token-here" ]; then
    echo -e "${RED}Error: Token not configured in $CONFIG_FILE${NC}"
    echo "Please add your OpsSquad token to the 'global.token' field"
    exit 1
fi

echo -e "${GREEN}Configuration loaded from: $CONFIG_FILE${NC}"
echo -e "Socket URL: $SOCKET_URL"
echo -e "Token: ${TOKEN:0:8}...${TOKEN: -4}"
echo ""

# Count enabled nodes
TOTAL_NODES=$(jq '[.nodes[] | select(.enabled == true and .node_id != "")] | length' "$CONFIG_FILE")
echo -e "Found ${BLUE}$TOTAL_NODES${NC} enabled nodes with IDs configured"
echo ""

if [ "$TOTAL_NODES" -eq 0 ]; then
    echo -e "${YELLOW}Warning: No nodes are configured with node IDs.${NC}"
    echo "Please edit nodes.json and add node IDs for each service."
    exit 1
fi

# Process each node
INSTALLED=0
FAILED=0
SKIPPED=0

echo -e "${BLUE}Installing nodes...${NC}"
echo "────────────────────────────────────────────────────────────────"

jq -c '.nodes[]' "$CONFIG_FILE" | while read -r node; do
    NAME=$(echo "$node" | jq -r '.name')
    CONTAINER=$(echo "$node" | jq -r '.container')
    NODE_ID=$(echo "$node" | jq -r '.node_id')
    ENABLED=$(echo "$node" | jq -r '.enabled')

    # Skip disabled nodes
    if [ "$ENABLED" != "true" ]; then
        echo -e "${YELLOW}⊘${NC} $NAME: Disabled, skipping"
        continue
    fi

    # Skip nodes without node ID
    if [ -z "$NODE_ID" ] || [ "$NODE_ID" == "null" ] || [ "$NODE_ID" == "" ]; then
        echo -e "${YELLOW}⊘${NC} $NAME: No node ID configured, skipping"
        continue
    fi

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo -e "${RED}✗${NC} $NAME: Container '$CONTAINER' not running"
        continue
    fi

    echo -ne "${BLUE}►${NC} $NAME ($CONTAINER): Installing..."

    # Install node in container
    INSTALL_OUTPUT=$(docker exec "$CONTAINER" bash -c "
        set -e

        # Add local bin to PATH
        export PATH=\"\$HOME/.local/bin:\$PATH\"

        # Check if already installed and running
        if command -v opssquad &> /dev/null && opssquad node status 2>/dev/null | grep -q 'RUNNING'; then
            echo 'ALREADY_RUNNING'
            exit 0
        fi

        # Clean up previous installation
        pkill -f opssquad-connectivity-layer 2>/dev/null || true
        rm -rf \$HOME/.local/bin/opssquad \$HOME/.local/lib/opssquad \$HOME/.config/opssquad 2>/dev/null || true

        # Step 1: Install the OpsSquad CLI
        curl -fsSL https://install.opssquad.ai/install.sh 2>/dev/null | bash 2>/dev/null

        # Step 2: Install the node with credentials
        \$HOME/.local/bin/opssquad node install --node-id=\"$NODE_ID\" --token=\"$TOKEN\"

        # Step 3: Start the node
        \$HOME/.local/bin/opssquad node start

        # Step 4: Verify status
        sleep 2
        if \$HOME/.local/bin/opssquad node status 2>/dev/null | grep -q 'RUNNING'; then
            echo 'SUCCESS'
        else
            echo 'NODE_START_FAILED'
        fi
    " 2>&1)

    # Check result
    if echo "$INSTALL_OUTPUT" | grep -q "SUCCESS"; then
        echo -e "\r${GREEN}✓${NC} $NAME ($CONTAINER): Node installed and running      "
    elif echo "$INSTALL_OUTPUT" | grep -q "ALREADY_RUNNING"; then
        echo -e "\r${BLUE}●${NC} $NAME ($CONTAINER): Node already running            "
    elif echo "$INSTALL_OUTPUT" | grep -q "NODE_START_FAILED"; then
        echo -e "\r${RED}✗${NC} $NAME ($CONTAINER): Node installed but failed to start"
    else
        echo -e "\r${RED}✗${NC} $NAME ($CONTAINER): Installation failed"
        echo "    Error: $(echo "$INSTALL_OUTPUT" | tail -3)"
    fi
done

echo "────────────────────────────────────────────────────────────────"
echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "To verify nodes are running:"
echo "  ./scripts/check-nodes.sh"
echo ""
echo "To view node logs in a specific container:"
echo "  docker exec <container> tail -f /var/log/opssquad-node.log"
echo ""
