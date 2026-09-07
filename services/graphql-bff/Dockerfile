FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY . .
ENV DD_LOGS_INJECTION=true
ENV NODE_ENV=production
ENV DD_PROFILING_ENABLED=true
CMD ["node", "server.js"]
