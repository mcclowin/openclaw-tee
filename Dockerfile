ARG OPENCLAW_VERSION=v2026.2.13

# --- Stage 1: Build OpenClaw from source (using their own Dockerfile pattern) ---
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

RUN apt-get update && apt-get install -y gosu openssl ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app /app
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node/.openclaw

WORKDIR /app
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
