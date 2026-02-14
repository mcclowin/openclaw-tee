# Brain&Bot OpenClaw TEE Image
# Builds official OpenClaw from source + our entrypoint
FROM node:22-bookworm AS builder

# Install Bun (required for OpenClaw build)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

WORKDIR /build

# Clone OpenClaw source
RUN git clone --depth 1 https://github.com/openclaw/openclaw.git .

# Install deps + build
RUN pnpm install --frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# Runtime stage — slim
FROM node:22-bookworm-slim

WORKDIR /app

# Copy built OpenClaw
COPY --from=builder /build/dist ./dist
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/package.json ./
COPY --from=builder /build/ui/dist ./ui/dist 

# Copy our entrypoint
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/opt/entrypoint.sh"]
