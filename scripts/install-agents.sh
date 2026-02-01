#!/bin/bash
#
# OpsSquad Agent Installation Script
# Reads nodes.json and installs agents on all configured containers
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
echo -e "${BLUE}║           OpsSquad Agent Installation Script               ║${NC}"
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
    echo "  2. Fill in your agent IDs and API key from the OpsSquad dashboard"
    echo "  3. Run this script again"
    echo ""
    echo "Example:"
    echo "  cp nodes.example.json nodes.json"
    echo "  # Edit nodes.json with your credentials"
    echo "  ./scripts/install-agents.sh"
    exit 1
fi

# Read global config
API_KEY=$(jq -r '.global.api_key' "$CONFIG_FILE")
SOCKET_URL=$(jq -r '.global.socket_url // "socket.opssquad.ai:9000"' "$CONFIG_FILE")

if [ -z "$API_KEY" ] || [ "$API_KEY" == "null" ] || [ "$API_KEY" == "your-opssquad-api-key-here" ]; then
    echo -e "${RED}Error: API key not configured in $CONFIG_FILE${NC}"
    echo "Please add your OpsSquad API key to the 'global.api_key' field"
    exit 1
fi

echo -e "${GREEN}Configuration loaded from: $CONFIG_FILE${NC}"
echo -e "Socket URL: $SOCKET_URL"
echo -e "API Key: ${API_KEY:0:8}...${API_KEY: -4}"
echo ""

# Count enabled nodes
TOTAL_NODES=$(jq '[.nodes[] | select(.enabled == true and .agent_id != "")] | length' "$CONFIG_FILE")
echo -e "Found ${BLUE}$TOTAL_NODES${NC} enabled nodes with agent IDs"
echo ""

if [ "$TOTAL_NODES" -eq 0 ]; then
    echo -e "${YELLOW}Warning: No nodes are configured with agent IDs.${NC}"
    echo "Please edit nodes.json and add agent IDs for each service."
    exit 1
fi

# Process each node
INSTALLED=0
FAILED=0
SKIPPED=0

echo -e "${BLUE}Installing agents...${NC}"
echo "────────────────────────────────────────────────────────────────"

jq -c '.nodes[]' "$CONFIG_FILE" | while read -r node; do
    NAME=$(echo "$node" | jq -r '.name')
    CONTAINER=$(echo "$node" | jq -r '.container')
    AGENT_ID=$(echo "$node" | jq -r '.agent_id')
    ENABLED=$(echo "$node" | jq -r '.enabled')

    # Skip disabled nodes
    if [ "$ENABLED" != "true" ]; then
        echo -e "${YELLOW}⊘${NC} $NAME: Disabled, skipping"
        continue
    fi

    # Skip nodes without agent ID
    if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" == "null" ] || [ "$AGENT_ID" == "" ]; then
        echo -e "${YELLOW}⊘${NC} $NAME: No agent ID configured, skipping"
        continue
    fi

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo -e "${RED}✗${NC} $NAME: Container '$CONTAINER' not running"
        continue
    fi

    echo -ne "${BLUE}►${NC} $NAME ($CONTAINER): Installing..."

    # Install agent in container
    INSTALL_OUTPUT=$(docker exec "$CONTAINER" bash -c "
        set -e

        # Clean up previous installation
        rm -rf \$HOME/.local/bin/fixpanic \$HOME/.local/lib/fixpanic \$HOME/.config/fixpanic 2>/dev/null || true

        # Download and install CLI
        curl -fsSL https://install.fixpanic.com/install.sh 2>/dev/null | bash 2>/dev/null

        # Add to PATH
        export PATH=\"\$HOME/.local/bin:\$PATH\"

        # Install agent
        \$HOME/.local/bin/fixpanic agent install --agent-id=\"$AGENT_ID\" --api-key=\"$API_KEY\" 2>/dev/null

        # Start agent in background
        AGENT_BINARY=\"\$HOME/.local/lib/fixpanic/fixpanic-connectivity-layer\"
        AGENT_CONFIG=\"\$HOME/.config/fixpanic/agent.yaml\"

        if [ -f \"\$AGENT_BINARY\" ] && [ -f \"\$AGENT_CONFIG\" ]; then
            # Kill any existing agent
            pkill -f fixpanic-connectivity-layer 2>/dev/null || true
            sleep 1

            # Start new agent
            nohup \"\$AGENT_BINARY\" --config \"\$AGENT_CONFIG\" > /var/log/opssquad-agent.log 2>&1 &
            sleep 2

            # Verify it's running
            if pgrep -f fixpanic-connectivity-layer > /dev/null; then
                echo 'SUCCESS'
            else
                echo 'AGENT_START_FAILED'
            fi
        else
            echo 'BINARY_NOT_FOUND'
        fi
    " 2>&1)

    # Check result
    if echo "$INSTALL_OUTPUT" | grep -q "SUCCESS"; then
        echo -e "\r${GREEN}✓${NC} $NAME ($CONTAINER): Agent installed and running    "
    elif echo "$INSTALL_OUTPUT" | grep -q "AGENT_START_FAILED"; then
        echo -e "\r${RED}✗${NC} $NAME ($CONTAINER): Agent installed but failed to start"
    elif echo "$INSTALL_OUTPUT" | grep -q "BINARY_NOT_FOUND"; then
        echo -e "\r${RED}✗${NC} $NAME ($CONTAINER): CLI installed but agent binary not found"
    else
        echo -e "\r${RED}✗${NC} $NAME ($CONTAINER): Installation failed"
        echo "    Error: $(echo "$INSTALL_OUTPUT" | tail -1)"
    fi
done

echo "────────────────────────────────────────────────────────────────"
echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "To verify agents are running:"
echo "  ./scripts/check-agents.sh"
echo ""
echo "To view agent logs in a specific container:"
echo "  docker exec <container> tail -f /var/log/opssquad-agent.log"
echo ""
