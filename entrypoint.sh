#!/bin/sh
set -e

# === OpenClaw TEE Entrypoint ===
# One file. Generates config, fixes permissions, seeds workspace, starts gateway.

CONFIG_DIR="/home/node/.openclaw"
AGENT_DIR="$CONFIG_DIR/agents/main/agent"
WORKSPACE="$CONFIG_DIR/workspace"

# --- Create all dirs OpenClaw expects ---
mkdir -p "$AGENT_DIR" "$WORKSPACE" \
  "$CONFIG_DIR/agents/main/sessions" \
  "$CONFIG_DIR/telegram" \
  "$CONFIG_DIR/canvas" \
  "$CONFIG_DIR/cron" \
  "$CONFIG_DIR/sandboxes"

# --- Fix ownership (if running as root, drop to node after) ---
if [ "$(id -u)" = "0" ]; then
  chown -R node:node "$CONFIG_DIR"
fi

# --- Validate required env vars ---
missing=""
[ -z "$ANTHROPIC_API_KEY" ] && missing="$missing ANTHROPIC_API_KEY"
[ -z "$TELEGRAM_BOT_TOKEN" ] && missing="$missing TELEGRAM_BOT_TOKEN"
[ -z "$TELEGRAM_OWNER_ID" ] && missing="$missing TELEGRAM_OWNER_ID"

if [ -n "$missing" ]; then
  echo "ERROR: Missing required env vars:$missing"
  exit 1
fi

# Auto-generate gateway token if not provided
GATEWAY_TOKEN="${GATEWAY_TOKEN:-$(head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n')}"

# --- Generate openclaw.json ---
cat > "$CONFIG_DIR/openclaw.json" << EOF
{
  "gateway": {
    "port": 3000,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${PRIMARY_MODEL:-claude-sonnet-4-20250514}"
      },
      "workspace": "$WORKSPACE"
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "$TELEGRAM_BOT_TOKEN",
      "allowFrom": ["$TELEGRAM_OWNER_ID"],
      "dmPolicy": "allowlist"
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      }
    }
  }
}
EOF

# --- Generate auth-profiles.json ---
cat > "$AGENT_DIR/auth-profiles.json" << EOF
{
  "version": 1,
  "profiles": {
    "anthropic:default": {
      "type": "token",
      "provider": "anthropic",
      "token": "$ANTHROPIC_API_KEY"
    }
  }
}
EOF

# --- Fix ownership again after writing configs ---
if [ "$(id -u)" = "0" ]; then
  chown -R node:node "$CONFIG_DIR"
fi

# --- Seed workspace files (only if not already present) ---
if [ -n "$SOUL_MD" ]; then
  echo "$SOUL_MD" > "$WORKSPACE/SOUL.md"
  echo "Injected SOUL.md from env"
elif [ -f /opt/config/SOUL.md ] && [ ! -f "$WORKSPACE/SOUL.md" ]; then
  cp /opt/config/SOUL.md "$WORKSPACE/SOUL.md"
  echo "Injected SOUL.md from mount"
fi

echo "=== OpenClaw TEE Deploy ==="
echo "Gateway token: $GATEWAY_TOKEN"
echo "Model: ${PRIMARY_MODEL:-anthropic:claude-sonnet-4-20250514}"
echo "Telegram owner: $TELEGRAM_OWNER_ID"
echo "==========================="

# --- Start OpenClaw (drop to node user if root) ---
if [ "$(id -u)" = "0" ]; then
  exec gosu node node openclaw.mjs gateway
else
  exec node openclaw.mjs gateway
fi
