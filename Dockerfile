FROM node:22-alpine

# Build tools needed for native modules (node-llama-cpp etc)
RUN apk add --no-cache openssl ca-certificates git python3 make g++ cmake

# Install OpenClaw from npm with full postinstall scripts
ENV NODE_LLAMA_CPP_SKIP_DOWNLOAD=true
RUN npm install -g openclaw@latest

# Clean up build tools to reduce image size
RUN apk del python3 make g++ cmake && rm -rf /tmp/* /root/.npm/_cacache

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
