# Stage 1: Build
FROM node:20.11-alpine3.19 AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --prefer-offline --no-audit

COPY . .

ARG VITE_APP_VERSION=v1.0.0
ARG VITE_COMMIT_SHA=unknown
ARG VITE_BUILD_TIME
ARG VITE_ENVIRONMENT=production
ARG VITE_CLUSTER_NAME=react-k8s-cluster

ENV VITE_APP_VERSION=$VITE_APP_VERSION \
    VITE_COMMIT_SHA=$VITE_COMMIT_SHA \
    VITE_BUILD_TIME=$VITE_BUILD_TIME \
    VITE_ENVIRONMENT=$VITE_ENVIRONMENT \
    VITE_CLUSTER_NAME=$VITE_CLUSTER_NAME

RUN npm run build

# Stage 2: Serve
FROM nginx:1.25-alpine3.18

RUN rm /etc/nginx/conf.d/default.conf && \
    rm -rf /usr/share/nginx/html/* && \
    # Pre-create all nginx cache and temp directories with correct permissions
    # This ensures they exist and are writable regardless of K8s securityContext
    mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp \
             /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp && \
    chown -R nginx:nginx /var/cache/nginx && \
    chmod -R 755 /var/cache/nginx && \
    chown -R nginx:nginx /var/run && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

RUN chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
