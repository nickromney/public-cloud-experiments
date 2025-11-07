# Stage 1: Build
FROM node:22-alpine AS builder

WORKDIR /app

# Build arguments for Vite environment variables
ARG VITE_API_URL=http://localhost:7071
ARG VITE_AUTH_METHOD=none
ARG VITE_AZURE_CLIENT_ID=
ARG VITE_AZURE_TENANT_ID=common
ARG VITE_AZURE_REDIRECT_URI=

# Set as environment variables for Vite build
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_AUTH_METHOD=$VITE_AUTH_METHOD
ENV VITE_AZURE_CLIENT_ID=$VITE_AZURE_CLIENT_ID
ENV VITE_AZURE_TENANT_ID=$VITE_AZURE_TENANT_ID
ENV VITE_AZURE_REDIRECT_URI=$VITE_AZURE_REDIRECT_URI

# Copy package files for dependency installation
COPY package.json package-lock.json ./

# Install dependencies (uses lock file for reproducible builds)
RUN npm ci

# Copy source code
COPY . .

# Build application (Vite will embed environment variables)
RUN npm run build

# Stage 2: Production
FROM nginx:alpine

# Copy built files from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# nginx starts automatically
