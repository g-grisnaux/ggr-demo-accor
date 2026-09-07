FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm install
COPY . .
# Vite inlines these at build time, so they must be present during the build
# rather than injected as container env vars at runtime.
ARG VITE_DD_RUM_APPLICATION_ID
ARG VITE_DD_RUM_CLIENT_TOKEN
ARG VITE_DD_SITE=datadoghq.com
ARG VITE_DD_SERVICE=all-web
ARG VITE_DD_ENV
ARG VITE_DD_VERSION=1.0.0
ARG VITE_CLIENT_NAME=all-web
ARG VITE_CLIENT_VERSION=3.4.0
ENV VITE_DD_RUM_APPLICATION_ID=$VITE_DD_RUM_APPLICATION_ID \
    VITE_DD_RUM_CLIENT_TOKEN=$VITE_DD_RUM_CLIENT_TOKEN \
    VITE_DD_SITE=$VITE_DD_SITE \
    VITE_DD_SERVICE=$VITE_DD_SERVICE \
    VITE_DD_ENV=$VITE_DD_ENV \
    VITE_DD_VERSION=$VITE_DD_VERSION \
    VITE_CLIENT_NAME=$VITE_CLIENT_NAME \
    VITE_CLIENT_VERSION=$VITE_CLIENT_VERSION
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
