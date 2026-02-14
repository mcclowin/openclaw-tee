# openclaw-tee

OpenClaw in a TEE. One image, env vars at runtime, zero wizard.

## Usage

```bash
docker run -d \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e TELEGRAM_BOT_TOKEN=... \
  -e TELEGRAM_OWNER_ID=... \
  ghcr.io/mcclowin/openclaw-tee:latest
```

## Env Vars

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | ✅ | Anthropic API key |
| `TELEGRAM_BOT_TOKEN` | ✅ | Telegram bot token |
| `TELEGRAM_OWNER_ID` | ✅ | Your Telegram user ID |
| `GATEWAY_TOKEN` | ❌ | Auto-generated if empty |
| `PRIMARY_MODEL` | ❌ | Default: claude-sonnet-4-20250514 |
| `SOUL_MD` | ❌ | Bot personality (SOUL.md content) |
