#!/bin/bash
#
# Generate .env file from nodes.json
# This allows docker-compose to auto-install OpsSquad nodes on container start
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
NODES_FILE="${1:-$DEMO_DIR/nodes.json}"
ENV_FILE="$DEMO_DIR/.env"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}Generating .env from nodes.json${NC}"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

# Check if nodes.json exists
if [ ! -f "$NODES_FILE" ]; then
    echo "Error: $NODES_FILE not found"
    echo "Copy nodes.example.json to nodes.json and add your credentials"
    exit 1
fi

# Start with the example file as base (for scenario settings)
if [ -f "$DEMO_DIR/.env.example" ]; then
    cp "$DEMO_DIR/.env.example" "$ENV_FILE"
else
    echo "# Auto-generated from nodes.json" > "$ENV_FILE"
    echo "" >> "$ENV_FILE"
fi

# Function to get env var prefix from container name
get_prefix() {
    case "$1" in
        "fintech-api-gateway") echo "API_GATEWAY" ;;
        "fintech-auth-service") echo "AUTH_SERVICE" ;;
        "fintech-account-service") echo "ACCOUNT_SERVICE" ;;
        "fintech-transaction-service") echo "TRANSACTION_SERVICE" ;;
        "fintech-fraud-detection") echo "FRAUD_SERVICE" ;;
        "fintech-notification-service") echo "NOTIFICATION_SERVICE" ;;
        "fintech-payment-processor") echo "PAYMENT_SERVICE" ;;
        *) echo "" ;;
    esac
}

# Create a temp file for the new values
TEMP_FILE=$(mktemp)

# Read nodes and update env vars
jq -c '.nodes[]' "$NODES_FILE" | while read -r node; do
    CONTAINER=$(echo "$node" | jq -r '.container')
    NODE_ID=$(echo "$node" | jq -r '.node_id')
    TOKEN=$(echo "$node" | jq -r '.token')
    ENABLED=$(echo "$node" | jq -r '.enabled')
    NAME=$(echo "$node" | jq -r '.name')

    if [ "$ENABLED" != "true" ]; then
        continue
    fi

    PREFIX=$(get_prefix "$CONTAINER")
    if [ -z "$PREFIX" ]; then
        echo -e "${YELLOW}Warning: Unknown container $CONTAINER, skipping${NC}"
        continue
    fi

    if [ -n "$NODE_ID" ] && [ "$NODE_ID" != "null" ] && [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
        echo "${PREFIX}_NODE_ID=$NODE_ID" >> "$TEMP_FILE"
        echo "${PREFIX}_TOKEN=$TOKEN" >> "$TEMP_FILE"
        echo -e "${GREEN}✓${NC} $NAME: credentials added"
    else
        echo -e "${YELLOW}⊘${NC} $NAME: missing node_id or token"
    fi
done

# Update .env with the new values
while IFS='=' read -r key value; do
    if [ -z "$key" ]; then continue; fi
    if grep -q "^${key}=" "$ENV_FILE"; then
        # Update existing key (macOS compatible sed)
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        # Append new key
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
done < "$TEMP_FILE"

rm -f "$TEMP_FILE" "$ENV_FILE.bak"

echo ""
echo -e "${GREEN}Generated $ENV_FILE${NC}"
echo ""
echo "Now you can start the demo with auto-installed nodes:"
echo "  ./scripts/start-demo.sh"
echo ""
