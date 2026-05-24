# ── Stage 1: Build Next.js frontend ──────────────────────────────────────────
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci --silent

COPY frontend/ ./

# Empty string = relative URLs → nginx routes them to FastAPI on same host
ENV NEXT_PUBLIC_API_URL=""
RUN npm run build

# ── Stage 2: Combined runtime ─────────────────────────────────────────────────
FROM python:3.11-slim

# System packages: nginx, supervisor, nodejs
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    supervisor \
    curl \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Python backend ─────────────────────────────────────────────────────────────
WORKDIR /app/backend
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ .

# ── Next.js standalone ─────────────────────────────────────────────────────────
WORKDIR /app/frontend
COPY --from=frontend-builder /app/frontend/.next/standalone ./
COPY --from=frontend-builder /app/frontend/.next/static  ./.next/static
COPY --from=frontend-builder /app/frontend/public        ./public

# ── Config files ───────────────────────────────────────────────────────────────
COPY nginx.conf       /etc/nginx/sites-available/default
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# HuggingFace Spaces requires port 7860
EXPOSE 7860

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
