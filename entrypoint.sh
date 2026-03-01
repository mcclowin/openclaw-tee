#!/bin/sh
set -e

echo "=== OpenClaw Entrypoint ==="
echo "Running as: $(id)"
echo "HOME: $HOME"

CONFIG_DIR="$HOME/.openclaw"
AGENT_DIR="$CONFIG_DIR/agents/main/agent"
WORKSPACE="$CONFIG_DIR/workspace"

# --- Create all dirs ---
mkdir -p "$AGENT_DIR" "$WORKSPACE" \
  "$CONFIG_DIR/agents/main/sessions" \
  "$CONFIG_DIR/telegram" \
  "$CONFIG_DIR/canvas" \
  "$CONFIG_DIR/cron" \
  "$CONFIG_DIR/sandboxes" \
  "$CONFIG_DIR/credentials"

# --- Validate ---
if [ -n "$OPENCLAW_CONFIG" ]; then
  # Advanced mode: user provides full config, only need API key for auth-profiles
  echo "Advanced mode: using OPENCLAW_CONFIG"
  if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "WARNING: No ANTHROPIC_API_KEY set. Make sure your auth is configured in OPENCLAW_CONFIG or custom env."
  fi
else
  # Easy mode: individual env vars required
  missing=""
  [ -z "$ANTHROPIC_API_KEY" ] && missing="$missing ANTHROPIC_API_KEY"
  [ -z "$TELEGRAM_BOT_TOKEN" ] && missing="$missing TELEGRAM_BOT_TOKEN"
  [ -z "$TELEGRAM_OWNER_ID" ] && missing="$missing TELEGRAM_OWNER_ID"

  if [ -n "$missing" ]; then
    echo "ERROR: Missing required env vars:$missing"
    exit 1
  fi
fi

GATEWAY_TOKEN="${GATEWAY_TOKEN:-$(head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n')}"

# --- Generate openclaw.json ---
if [ -n "$OPENCLAW_CONFIG" ]; then
  echo "Using custom openclaw.json from OPENCLAW_CONFIG env var"
  # Handle escaped newlines from env var (Phala encrypted_env escapes \n)
  printf '%b' "$OPENCLAW_CONFIG" > "$CONFIG_DIR/openclaw.json"
  # Validate JSON before proceeding
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json; json.load(open('$CONFIG_DIR/openclaw.json'))" 2>/dev/null || {
      echo "WARN: openclaw.json not valid JSON, attempting to fix escaped newlines..."
      echo "$OPENCLAW_CONFIG" | sed 's/\\n/\n/g; s/\\t/\t/g' > "$CONFIG_DIR/openclaw.json"
    }
  fi
  
  # Inject gateway settings (port, auth) into custom config so the TEE is reachable
  # Uses python3 if available, otherwise node
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys
with open('$CONFIG_DIR/openclaw.json') as f:
    cfg = json.load(f)
cfg.setdefault('gateway', {})
cfg['gateway']['port'] = 3000
cfg['gateway']['mode'] = 'local'
cfg['gateway']['bind'] = 'lan'
cfg['gateway'].setdefault('auth', {})
cfg['gateway']['auth']['mode'] = 'token'
cfg['gateway']['auth']['token'] = '$GATEWAY_TOKEN'
cfg['gateway']['controlUi'] = {'dangerouslyAllowHostHeaderOriginFallback': True}
cfg.setdefault('wizard', {})
cfg['wizard']['lastRunAt'] = '2026-01-01T00:00:00.000Z'
cfg['wizard']['lastRunVersion'] = '2026.2.13'
cfg['wizard']['lastRunCommand'] = 'onboard'
cfg['wizard']['lastRunMode'] = 'local'
cfg.setdefault('agents', {}).setdefault('defaults', {})
cfg['agents']['defaults']['workspace'] = '$WORKSPACE'
# Inject Telegram token + owner into channels.telegram if present in env
if '$TELEGRAM_BOT_TOKEN':
    cfg.setdefault('channels', {}).setdefault('telegram', {})
    cfg['channels']['telegram']['enabled'] = True
    cfg['channels']['telegram']['botToken'] = '$TELEGRAM_BOT_TOKEN'
    if '$TELEGRAM_OWNER_ID':
        cfg['channels']['telegram']['allowFrom'] = ['$TELEGRAM_OWNER_ID']
        cfg['channels']['telegram']['dmPolicy'] = 'allowlist'
with open('$CONFIG_DIR/openclaw.json', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>&1 || echo "Warning: failed to merge gateway into custom config"
  else
    node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('$CONFIG_DIR/openclaw.json','utf8'));
cfg.gateway = {...(cfg.gateway||{}), port:3000, mode:'local', bind:'lan', auth:{mode:'token',token:'$GATEWAY_TOKEN'}, controlUi:{dangerouslyAllowHostHeaderOriginFallback:true}};
cfg.wizard = {lastRunAt:'2026-01-01T00:00:00.000Z',lastRunVersion:'2026.2.13',lastRunCommand:'onboard',lastRunMode:'local'};
cfg.agents = cfg.agents||{}; cfg.agents.defaults = cfg.agents.defaults||{}; cfg.agents.defaults.workspace='$WORKSPACE';
if('$TELEGRAM_BOT_TOKEN'){cfg.channels=cfg.channels||{};cfg.channels.telegram={...(cfg.channels.telegram||{}),enabled:true,botToken:'$TELEGRAM_BOT_TOKEN'};}
if('$TELEGRAM_OWNER_ID'){cfg.channels.telegram.allowFrom=['$TELEGRAM_OWNER_ID'];cfg.channels.telegram.dmPolicy='allowlist';}
fs.writeFileSync('$CONFIG_DIR/openclaw.json',JSON.stringify(cfg,null,2));
" 2>&1 || echo "Warning: failed to merge gateway into custom config"
  fi
else
  echo "Generating default openclaw.json"
  cat > "$CONFIG_DIR/openclaw.json" << JSONEOF
{
  "wizard": {
    "lastRunAt": "2026-01-01T00:00:00.000Z",
    "lastRunVersion": "2026.2.13",
    "lastRunCommand": "onboard",
    "lastRunMode": "local"
  },
  "auth": {
    "profiles": {
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "token"
      }
    }
  },
  "gateway": {
    "port": 3000,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    },
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-20250514"
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
  }
}
JSONEOF
fi

# --- Generate auth-profiles.json ---
# Check for API key in env (works for both easy and advanced mode)
if [ -n "$ANTHROPIC_API_KEY" ]; then
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
  echo "Generated auth-profiles.json with ANTHROPIC_API_KEY"
elif [ -n "$OPENAI_API_KEY" ]; then
  cat > "$AGENT_DIR/auth-profiles.json" << JSONEOF
{
  "version": 1,
  "profiles": {
    "openai:default": {
      "type": "token",
      "provider": "openai",
      "token": "$OPENAI_API_KEY"
    }
  }
}
JSONEOF
  echo "Generated auth-profiles.json with OPENAI_API_KEY"
else
  echo "ERROR: No API key found. Set ANTHROPIC_API_KEY or OPENAI_API_KEY as a custom env var."
  echo "In advanced mode, the API key must be passed as a separate environment variable (not inside openclaw.json)."
  exit 1
fi

# --- Seed workspace files ---
if [ -n "$SOUL_MD" ]; then
  echo "$SOUL_MD" > "$WORKSPACE/SOUL.md"
  echo "Seeded SOUL.md"
fi
if [ -n "$AGENTS_MD" ]; then
  echo "$AGENTS_MD" > "$WORKSPACE/AGENTS.md"
  echo "Seeded AGENTS.md"
fi
if [ -n "$TOOLS_MD" ]; then
  echo "$TOOLS_MD" > "$WORKSPACE/TOOLS.md"
  echo "Seeded TOOLS.md"
fi
if [ -n "$USER_MD" ]; then
  echo "$USER_MD" > "$WORKSPACE/USER.md"
  echo "Seeded USER.md"
fi
if [ -n "$HEARTBEAT_MD" ]; then
  echo "$HEARTBEAT_MD" > "$WORKSPACE/HEARTBEAT.md"
  echo "Seeded HEARTBEAT.md"
fi
if [ -n "$MEMORY_MD" ]; then
  echo "$MEMORY_MD" > "$WORKSPACE/MEMORY.md"
  echo "Seeded MEMORY.md"
fi

echo "Gateway token: $GATEWAY_TOKEN"
echo "Telegram owner: $TELEGRAM_OWNER_ID"
echo "Config dir: $CONFIG_DIR"
cat "$CONFIG_DIR/openclaw.json"
echo "=== OpenClaw Version ==="
openclaw --version 2>&1 || echo "version check failed"

echo "=== Running Doctor Fix ==="
openclaw doctor --fix 2>&1 || echo "doctor fix failed (non-fatal)"

echo "=== Starting Gateway ==="

# openclaw installed globally via npm
exec openclaw gateway 2>&1
