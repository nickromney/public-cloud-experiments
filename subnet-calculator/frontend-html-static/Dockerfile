# Dockerfile for static HTML frontend with nginx
FROM nginx:alpine

# Copy static HTML, CSS, JS files, and favicon
COPY index.html /usr/share/nginx/html/
COPY favicon.svg /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/
COPY js/ /usr/share/nginx/html/js/

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# nginx will run as default (starts automatically from base image)
