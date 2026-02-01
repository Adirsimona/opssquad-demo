#!/bin/bash
set -e

echo "=========================================="
echo "FinTech API Gateway Starting"
echo "=========================================="

# Check if OpsSquad agent credentials are provided
if [ -n "$OPSSQUAD_AGENT_ID" ] && [ -n "$OPSSQUAD_API_KEY" ]; then
    echo "Agent ID: $OPSSQUAD_AGENT_ID"
    echo "Container: $(hostname)"
    echo "=========================================="

    # Clean up any previous installation
    echo "Cleaning up previous installation..."
    rm -rf "$HOME/.local/bin/fixpanic" "$HOME/.local/lib/fixpanic" "$HOME/.config/fixpanic" 2>/dev/null || true

    # Get latest version from GitHub redirect
    echo "Fetching latest version..."
    export VERSION=$(curl -sI https://github.com/fixpanic/fixpanic-cli-tool/releases/latest | grep -i location | sed 's/.*tag\///' | tr -d '\r\n')
    echo "Latest version: $VERSION"

    # Install OpsSquad CLI
    echo "Downloading OpsSquad CLI..."
    if curl -fsSL https://install.fixpanic.com/install.sh | bash; then
        echo "OpsSquad CLI installed"

        # Add to PATH
        export PATH="$HOME/.local/bin:$PATH"
        OPSSQUAD_BIN="$HOME/.local/bin/fixpanic"

        # Install agent
        echo "Installing agent..."
        if "$OPSSQUAD_BIN" agent install --agent-id="$OPSSQUAD_AGENT_ID" --api-key="$OPSSQUAD_API_KEY"; then
            echo "Agent configured"

            # Start agent binary in background
            echo "Starting agent..."
            AGENT_BINARY="$HOME/.local/lib/fixpanic/fixpanic-connectivity-layer"
            AGENT_CONFIG="$HOME/.config/fixpanic/agent.yaml"
            if [ -f "$AGENT_BINARY" ] && [ -f "$AGENT_CONFIG" ]; then
                nohup "$AGENT_BINARY" --config "$AGENT_CONFIG" > /var/log/opssquad-agent.log 2>&1 &
                AGENT_PID=$!
                sleep 1
                if kill -0 $AGENT_PID 2>/dev/null; then
                    echo "Agent started (PID: $AGENT_PID)"
                else
                    echo "Agent failed to start (check logs)"
                fi
            else
                echo "Agent binary or config not found"
            fi
        else
            echo "Failed to configure agent"
        fi
    else
        echo "Failed to download OpsSquad CLI"
    fi
else
    echo "No agent credentials provided, skipping installation"
fi

echo "=========================================="
echo "Starting nginx..."
echo "=========================================="

# Execute the main command
exec "$@"
