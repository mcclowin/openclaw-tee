#!/bin/sh
set -e

# === OpenClaw TEE Entrypoint ===
# Generates config from env vars, then starts OpenClaw gateway.

HOME_DIR="/home/node"
CONFIG_DIR="$HOME_DIR/.openclaw"
AGENT_DIR="$CONFIG_DIR/agents/main/agent"
WORKSPACE="$CONFIG_DIR/workspace"

echo "=== OpenClaw TEE Entrypoint ==="

# --- Create all dirs OpenClaw expects ---
mkdir -p "$AGENT_DIR" "$WORKSPACE" \
  "$CONFIG_DIR/agents/main/sessions" \
  "$CONFIG_DIR/telegram" \
  "$CONFIG_DIR/canvas" \
  "$CONFIG_DIR/cron" \
  "$CONFIG_DIR/sandboxes" \
  "$CONFIG_DIR/credentials"

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
cat > "$CONFIG_DIR/openclaw.json" << JSONEOF
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
JSONEOF

# --- Generate auth-profiles.json ---
cat > "$AGENT_DIR/auth-profiles.json" << JSONEOF
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
JSONEOF

# --- Seed workspace files ---
if [ -n "$SOUL_MD" ]; then
  echo "$SOUL_MD" > "$WORKSPACE/SOUL.md"
  echo "Seeded SOUL.md from env"
fi

# --- Fix ownership ---
chown -R node:node "$CONFIG_DIR"

echo "Gateway token: $GATEWAY_TOKEN"
echo "Model: ${PRIMARY_MODEL:-claude-sonnet-4-20250514}"
echo "Telegram owner: $TELEGRAM_OWNER_ID"
echo "Config written to: $CONFIG_DIR/openclaw.json"
echo "=== Starting OpenClaw Gateway ==="

# --- Start as node user ---
cd /app
exec gosu node node openclaw.mjs gateway
