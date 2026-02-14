# Brain&Bot OpenClaw TEE Image
# Builds official OpenClaw from source + our entrypoint
FROM node:22-bookworm

# Install Bun (required for OpenClaw build)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

WORKDIR /app

# Clone OpenClaw source
RUN git clone --depth 1 https://github.com/openclaw/openclaw.git /tmp/openclaw-src

# Copy source to working dir
RUN cp -r /tmp/openclaw-src/package.json /tmp/openclaw-src/pnpm-lock.yaml /tmp/openclaw-src/pnpm-workspace.yaml /tmp/openclaw-src/.npmrc ./
RUN cp -r /tmp/openclaw-src/ui ./ui
RUN cp -r /tmp/openclaw-src/patches ./patches
RUN cp -r /tmp/openclaw-src/scripts ./scripts

RUN pnpm install --frozen-lockfile

RUN cp -r /tmp/openclaw-src/* .
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# Clean up source
RUN rm -rf /tmp/openclaw-src

ENV NODE_ENV=production

# Copy our entrypoint
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/opt/entrypoint.sh"]
