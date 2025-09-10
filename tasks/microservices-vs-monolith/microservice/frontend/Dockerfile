FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html

# Configure reverse proxy
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/

EXPOSE 80
