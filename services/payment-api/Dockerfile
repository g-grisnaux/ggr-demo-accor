FROM node:22-alpine
WORKDIR /app
# curl is needed to reach the /admin scenario endpoints from inside the pod;
# the alpine base has none and scripts/scenario.sh depends on it.
RUN apk add --no-cache curl
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY . .
ENV DD_LOGS_INJECTION=true
ENV NODE_ENV=production
ENV DD_PROFILING_ENABLED=true
CMD ["node", "server.js"]
