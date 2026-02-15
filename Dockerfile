ARG OPENCLAW_VERSION=v2026.2.13

# --- Stage 1: Build OpenClaw from source ---
FROM node:22-bookworm AS builder

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

ARG OPENCLAW_VERSION
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} https://github.com/openclaw/openclaw.git /app
WORKDIR /app

RUN pnpm install --frozen-lockfile || pnpm install
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build || true

# --- Stage 2: Production image ---
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y openssl ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app /app
# Verify build output exists
RUN ls -la /app/openclaw.mjs /app/dist/ && echo "Build artifacts present"
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Run as root in TEE (hardware enclave IS the security boundary)

WORKDIR /app
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
