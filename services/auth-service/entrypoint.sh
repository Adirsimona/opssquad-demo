#!/bin/bash
set -e

echo "=========================================="
echo "FinTech Auth Service Starting"
echo "=========================================="

# Check if OpsSquad agent credentials are provided
if [ -n "$OPSSQUAD_AGENT_ID" ] && [ -n "$OPSSQUAD_API_KEY" ]; then
    echo "Agent ID: $OPSSQUAD_AGENT_ID"
    echo "Container: $(hostname)"
    echo "=========================================="

    # Clean up any previous installation
    rm -rf "$HOME/.local/bin/fixpanic" "$HOME/.local/lib/fixpanic" "$HOME/.config/fixpanic" 2>/dev/null || true

    # Get latest version
    export VERSION=$(curl -sI https://github.com/fixpanic/fixpanic-cli-tool/releases/latest 2>/dev/null | grep -i location | sed 's/.*tag\///' | tr -d '\r\n')

    # Install OpsSquad CLI
    if curl -fsSL https://install.fixpanic.com/install.sh 2>/dev/null | bash; then
        export PATH="$HOME/.local/bin:$PATH"

        if "$HOME/.local/bin/fixpanic" agent install --agent-id="$OPSSQUAD_AGENT_ID" --api-key="$OPSSQUAD_API_KEY" 2>/dev/null; then
            AGENT_BINARY="$HOME/.local/lib/fixpanic/fixpanic-connectivity-layer"
            AGENT_CONFIG="$HOME/.config/fixpanic/agent.yaml"
            if [ -f "$AGENT_BINARY" ] && [ -f "$AGENT_CONFIG" ]; then
                nohup "$AGENT_BINARY" --config "$AGENT_CONFIG" > /var/log/opssquad-agent.log 2>&1 &
                echo "OpsSquad agent started"
            fi
        fi
    fi
else
    echo "No agent credentials, skipping OpsSquad setup"
fi

echo "=========================================="
echo "Starting Node.js application..."
echo "=========================================="

exec node server.js
