#!/bin/bash
#
# OpsSquad Node Installation Script
# Reads nodes.json and installs OpsSquad nodes on all configured containers
#

# Don't use set -e as it causes issues with the while loop and docker exec

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
SOCKET_URL=$(jq -r '.global.socket_url // "socket.opssquad.ai:9000"' "$CONFIG_FILE")

echo -e "${GREEN}Configuration loaded from: $CONFIG_FILE${NC}"
echo -e "Socket URL: $SOCKET_URL"
echo ""

# Count enabled nodes with both node_id and token
TOTAL_NODES=$(jq '[.nodes[] | select(.enabled == true and .node_id != "" and .node_id != null and .token != "" and .token != null)] | length' "$CONFIG_FILE")
echo -e "Found ${BLUE}$TOTAL_NODES${NC} enabled nodes with credentials configured"
echo ""

if [ "$TOTAL_NODES" -eq 0 ]; then
    echo -e "${YELLOW}Warning: No nodes are configured with node_id and token.${NC}"
    echo "Please edit nodes.json and add node_id and token for each service."
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
    TOKEN=$(echo "$node" | jq -r '.token')
    ENABLED=$(echo "$node" | jq -r '.enabled')

    # Skip disabled nodes
    if [ "$ENABLED" != "true" ]; then
        echo -e "${YELLOW}⊘${NC} $NAME: Disabled, skipping"
        continue
    fi

    # Skip nodes without node ID
    if [ -z "$NODE_ID" ] || [ "$NODE_ID" == "null" ] || [ "$NODE_ID" == "" ]; then
        echo -e "${YELLOW}⊘${NC} $NAME: No node_id configured, skipping"
        continue
    fi

    # Skip nodes without token
    if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ] || [ "$TOKEN" == "" ]; then
        echo -e "${YELLOW}⊘${NC} $NAME: No token configured, skipping"
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
        # Add both possible bin locations to PATH
        export PATH=\"/usr/local/bin:\$HOME/.local/bin:\$PATH\"

        # Check if already installed and running
        if command -v opssquad &> /dev/null && opssquad node status 2>&1 | grep -q 'RUNNING'; then
            echo 'ALREADY_RUNNING'
            exit 0
        fi

        # Clean up previous installation
        pkill -f opssquad-connectivity-layer 2>/dev/null || true

        # Step 1: Install the OpsSquad CLI (download script first, then execute)
        curl -fsSL https://install.opssquad.ai/install.sh -o /tmp/install-opssquad.sh
        bash /tmp/install-opssquad.sh > /dev/null 2>&1
        rm -f /tmp/install-opssquad.sh

        # Verify CLI was installed
        if ! command -v opssquad &> /dev/null; then
            echo 'CLI_INSTALL_FAILED'
            exit 1
        fi

        # Step 2: Install the node with credentials
        opssquad node install --node-id=\"$NODE_ID\" --token=\"$TOKEN\" > /dev/null 2>&1

        # Step 3: Start the node
        opssquad node start > /dev/null 2>&1

        # Step 4: Verify status
        sleep 2
        if opssquad node status 2>&1 | grep -q 'RUNNING'; then
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
    elif echo "$INSTALL_OUTPUT" | grep -q "CLI_INSTALL_FAILED"; then
        echo -e "\r${RED}✗${NC} $NAME ($CONTAINER): Failed to install OpsSquad CLI"
    elif echo "$INSTALL_OUTPUT" | grep -q "NODE_START_FAILED"; then
        echo -e "\r${RED}✗${NC} $NAME ($CONTAINER): Node installed but failed to start"
    else
        echo -e "\r${RED}✗${NC} $NAME ($CONTAINER): Installation failed"
        echo "    Output: $(echo "$INSTALL_OUTPUT" | tail -5)"
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
