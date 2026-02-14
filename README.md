# openclaw-tee

OpenClaw in a Docker container, configured via environment variables. No wizard, no interaction.

Built by [Brain&Bot Technologies](https://brainandbot.gg).

## Quick Start

```bash
docker run -d --name my-bot --user root \
  -e ANTHROPIC_API_KEY="sk-ant-xxx" \
  -e TELEGRAM_BOT_TOKEN="123:ABC" \
  -e TELEGRAM_OWNER_ID="your_telegram_id" \
  -p 3000:3000 \
  ghcr.io/mcclowin/openclaw-tee:latest
```

That's it. Your bot is live on Telegram.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | ✅ | — | Anthropic API key |
| `TELEGRAM_BOT_TOKEN` | ✅ | — | From @BotFather |
| `TELEGRAM_OWNER_ID` | ✅ | — | Your Telegram user ID |
| `GATEWAY_TOKEN` | ❌ | auto-generated | Gateway auth token |
| `PRIMARY_MODEL` | ❌ | claude-sonnet-4-20250514 | LLM model |
| `SOUL_MD` | ❌ | — | Bot personality (markdown text) |

## How It Works

One `entrypoint.sh` that:
1. Validates required env vars
2. Generates `openclaw.json` config
3. Generates `auth-profiles.json`
4. Seeds optional `SOUL.md`
5. Starts OpenClaw gateway

OpenClaw runs unmodified inside. We just automate the config.

## TEE Deployment

This image is designed to run inside Phala Cloud CVMs (Intel TDX). Secrets are encrypted via KMS and only decrypted inside the TEE enclave.

## License

OpenClaw is licensed under its own terms. This wrapper is MIT.
