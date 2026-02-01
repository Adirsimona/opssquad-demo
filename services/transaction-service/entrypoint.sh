#!/bin/bash
set -e

echo "=========================================="
echo "FinTech Transaction Service Starting"
echo "=========================================="

if [ -n "$OPSSQUAD_AGENT_ID" ] && [ -n "$OPSSQUAD_API_KEY" ]; then
    echo "Agent ID: $OPSSQUAD_AGENT_ID"
    rm -rf "$HOME/.local/bin/fixpanic" "$HOME/.local/lib/fixpanic" "$HOME/.config/fixpanic" 2>/dev/null || true
    export VERSION=$(curl -sI https://github.com/fixpanic/fixpanic-cli-tool/releases/latest 2>/dev/null | grep -i location | sed 's/.*tag\///' | tr -d '\r\n')
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

echo "Starting Node.js application..."
exec node server.js
