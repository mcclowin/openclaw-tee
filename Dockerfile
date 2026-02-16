FROM node:22-alpine

RUN apk add --no-cache openssl ca-certificates git

# Install OpenClaw from npm (55MB vs 2.9GB from source)
RUN npm install -g openclaw@latest

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
