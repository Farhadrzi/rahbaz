FROM node:22-alpine

ENV NODE_ENV=production \
    RAHBAZ_PORT=8791 \
    RAHBAZ_LOG_DIR=/logs \
    RAHBAZ_SWITCH_LOG=/switch-out/switches.jsonl

WORKDIR /app

# Zero runtime dependencies: nothing to `npm install`.
COPY package.json ./
COPY src ./src

# /logs is normally a read-only bind mount of the proxy's log dir; /switch-out
# is where switches.jsonl is appended. Pre-create both owned by the unprivileged
# `node` user so they also work when left as anonymous/named volumes.
RUN mkdir -p /logs /switch-out && chown node:node /logs /switch-out

USER node
EXPOSE 8791

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=5 \
  CMD wget -qO- "http://127.0.0.1:${RAHBAZ_PORT}/health" >/dev/null || exit 1

CMD ["node", "src/server.js"]
