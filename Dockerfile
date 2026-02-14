FROM node:22-bookworm AS builder

# Install build tools
RUN apt-get update && apt-get install -y git python3 make g++ && rm -rf /var/lib/apt/lists/*
RUN npm install -g pnpm@9 bun@1

# Clone and build OpenClaw
ARG OPENCLAW_VERSION=main
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} https://github.com/anthropics/claude-code.git /build
WORKDIR /build
RUN bun install --frozen-lockfile || bun install
RUN pnpm install --frozen-lockfile || pnpm install  
RUN pnpm build
RUN pnpm ui:build || true

# --- Production image ---
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y su-exec openssl ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy built OpenClaw
COPY --from=builder /build /app

# Copy our entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create node user dirs
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node/.openclaw

WORKDIR /app
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
