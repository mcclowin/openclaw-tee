ARG OPENCLAW_VERSION=v2026.2.13

# --- Stage 1: Build OpenClaw from source ---
FROM node:22-bookworm AS builder

RUN corepack enable

ARG OPENCLAW_VERSION
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} https://github.com/openclaw/openclaw.git /app
WORKDIR /app

RUN pnpm install --frozen-lockfile || pnpm install
RUN pnpm build
RUN pnpm ui:build || true

# Prune dev dependencies to shrink node_modules
RUN pnpm prune --prod || true

# Remove unnecessary files
RUN rm -rf .git .github docs tests test src/test* \
    *.md LICENSE .eslintrc* .prettierrc* tsconfig* \
    node_modules/.cache node_modules/.package-lock.json

# --- Stage 2: Production image ---
FROM node:22-alpine

RUN apk add --no-cache openssl ca-certificates

COPY --from=builder /app/openclaw.mjs /app/openclaw.mjs
COPY --from=builder /app/dist /app/dist
COPY --from=builder /app/node_modules /app/node_modules
COPY --from=builder /app/package.json /app/package.json
COPY --from=builder /app/web /app/web
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
