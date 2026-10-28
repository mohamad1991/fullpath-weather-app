# syntax=docker/dockerfile:1.7
FROM node:22-alpine3.24 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Unprivileged nginx: listens on 8080, runs as uid 101 - no root, no NET_BIND_SERVICE.
FROM nginxinc/nginx-unprivileged:1.30-alpine3.24
# Pick up Alpine security fixes newer than the upstream image, and drop curl: a static
# file server never needs an HTTP client, and an attacker in the container would.
USER root
RUN apk upgrade --no-cache && apk del --no-cache curl
USER 101
ENV API_UPSTREAM=http://api:8000
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
