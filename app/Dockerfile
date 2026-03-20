# ─── Stage 1: Build ───────────────────────────────────────────────
# Pin exact version for reproducibility + supply chain security
FROM node:20.11-alpine3.19 AS builder

WORKDIR /app

# Copy manifests first — leverages Docker layer cache
# Re-runs npm ci only when package*.json changes
COPY package*.json ./
RUN npm ci --prefer-offline --no-audit

# Copy source and inject build-time metadata as env vars
# These are read by Vite (VITE_ prefix) and embedded into the bundle
COPY . .

ARG VITE_APP_VERSION=v1.0.0
ARG VITE_COMMIT_SHA=unknown
ARG VITE_BUILD_TIME
ARG VITE_ENVIRONMENT=production
ARG VITE_CLUSTER_NAME=kind-webapp-cluster

ENV VITE_APP_VERSION=$VITE_APP_VERSION \
    VITE_COMMIT_SHA=$VITE_COMMIT_SHA \
    VITE_BUILD_TIME=$VITE_BUILD_TIME \
    VITE_ENVIRONMENT=$VITE_ENVIRONMENT \
    VITE_CLUSTER_NAME=$VITE_CLUSTER_NAME

RUN npm run build

# ─── Stage 2: Serve ───────────────────────────────────────────────
# Minimal attack surface: alpine nginx, no build tools
FROM nginx:1.25-alpine3.18

# Remove default nginx config and default page
RUN rm /etc/nginx/conf.d/default.conf && \
    rm -rf /usr/share/nginx/html/*

# Copy our hardened nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built assets from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Run as non-root user (nginx user already exists in the image)
# nginx master process needs root to bind port 80 briefly, worker uses nginx user
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

EXPOSE 80

# Health check — used by Docker and can be scraped by K8s probes
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
