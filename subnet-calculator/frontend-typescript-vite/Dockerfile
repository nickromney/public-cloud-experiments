# Stage 1: Build
FROM node:22-alpine AS builder

WORKDIR /app

# Build arguments for Vite environment variables
ARG VITE_AUTH_ENABLED=false
ARG VITE_JWT_USERNAME=
ARG VITE_JWT_PASSWORD=
ARG VITE_API_URL=http://localhost:8090

# Set as environment variables for Vite build
ENV VITE_AUTH_ENABLED=$VITE_AUTH_ENABLED
ENV VITE_JWT_USERNAME=$VITE_JWT_USERNAME
ENV VITE_JWT_PASSWORD=$VITE_JWT_PASSWORD
ENV VITE_API_URL=$VITE_API_URL

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
