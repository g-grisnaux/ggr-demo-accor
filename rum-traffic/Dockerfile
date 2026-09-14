# The official Playwright image already carries Chromium and every system
# library it needs, which is the whole reason to use it rather than installing
# a browser into a slim base.
FROM mcr.microsoft.com/playwright:v1.49.0-noble

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY browse.js ./

CMD ["node", "browse.js"]
