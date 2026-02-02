#!/bin/bash
set -e

echo "=========================================="
echo "FinTech Account Service Starting"
echo "=========================================="

# Check if OpsSquad node credentials are provided
if [ -n "$OPSSQUAD_NODE_ID" ] && [ -n "$OPSSQUAD_TOKEN" ]; then
    echo "Node ID: $OPSSQUAD_NODE_ID"
    echo "Container: $(hostname)"
    echo "=========================================="

    export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

    if command -v opssquad &> /dev/null && opssquad node status 2>&1 | grep -q 'RUNNING'; then
        echo "OpsSquad node already running"
    else
        pkill -f opssquad-connectivity-layer 2>/dev/null || true
        rm -rf /usr/local/bin/opssquad /usr/local/lib/opssquad /etc/opssquad 2>/dev/null || true

        echo "Installing OpsSquad CLI..."
        if curl -fsSL https://install.opssquad.ai/install.sh -o /tmp/install-opssquad.sh && bash /tmp/install-opssquad.sh; then
            rm -f /tmp/install-opssquad.sh
            if opssquad node install --node-id="$OPSSQUAD_NODE_ID" --token="$OPSSQUAD_TOKEN"; then
                if opssquad node start; then
                    sleep 2
                    opssquad node status 2>&1 | grep -q 'RUNNING' && echo "OpsSquad node started successfully"
                fi
            fi
        fi
    fi
else
    echo "No node credentials, skipping OpsSquad setup"
fi

echo "=========================================="
echo "Starting Node.js application..."
echo "=========================================="

exec node server.js
