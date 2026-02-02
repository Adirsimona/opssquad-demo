#!/bin/bash
set -e

echo "=========================================="
echo "FinTech API Gateway Starting"
echo "=========================================="

# Check if OpsSquad node credentials are provided
if [ -n "$OPSSQUAD_NODE_ID" ] && [ -n "$OPSSQUAD_TOKEN" ]; then
    echo "Node ID: $OPSSQUAD_NODE_ID"
    echo "Container: $(hostname)"
    echo "=========================================="

    # Add CLI to PATH
    export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

    # Check if already running
    if command -v opssquad &> /dev/null && opssquad node status 2>&1 | grep -q 'RUNNING'; then
        echo "OpsSquad node already running"
    else
        # Clean up any previous installation
        echo "Cleaning up previous installation..."
        pkill -f opssquad-connectivity-layer 2>/dev/null || true
        rm -rf /usr/local/bin/opssquad /usr/local/lib/opssquad /etc/opssquad 2>/dev/null || true

        # Install OpsSquad CLI
        echo "Installing OpsSquad CLI..."
        if curl -fsSL https://install.opssquad.ai/install.sh -o /tmp/install-opssquad.sh && bash /tmp/install-opssquad.sh; then
            rm -f /tmp/install-opssquad.sh
            echo "OpsSquad CLI installed"

            # Install node with credentials
            echo "Installing node..."
            if opssquad node install --node-id="$OPSSQUAD_NODE_ID" --token="$OPSSQUAD_TOKEN"; then
                echo "Node configured"

                # Start node in background
                echo "Starting node..."
                if opssquad node start; then
                    sleep 2
                    if opssquad node status 2>&1 | grep -q 'RUNNING'; then
                        echo "OpsSquad node started successfully"
                    else
                        echo "Node may not be running (check logs)"
                    fi
                else
                    echo "Failed to start node"
                fi
            else
                echo "Failed to configure node"
            fi
        else
            echo "Failed to install OpsSquad CLI"
            rm -f /tmp/install-opssquad.sh
        fi
    fi
else
    echo "No node credentials provided, skipping OpsSquad installation"
fi

echo "=========================================="
echo "Starting nginx..."
echo "=========================================="

# Execute the main command
exec "$@"
