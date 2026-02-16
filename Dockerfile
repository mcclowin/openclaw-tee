FROM node:22-alpine

RUN apk add --no-cache openssl ca-certificates git

# Install OpenClaw from npm (~300MB vs 2.9GB from source)
# Skip node-llama-cpp native build (not needed for cloud API usage)
ENV NODE_LLAMA_CPP_SKIP_DOWNLOAD=true
RUN npm install -g --ignore-scripts openclaw@latest

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
