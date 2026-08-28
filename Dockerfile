# Serve the pre-built Unity WebGL player on Railway with nginx.
#
# This image expects the WebGL build to already exist at webgl/Build/ (produced
# by the headless BuildScript — see README). It copies that build into the nginx
# web root and serves it, substituting Railway's $PORT into the server config.
#
# Build context = the webgl/ folder:  docker build -f Dockerfile .
FROM nginx:1.27-alpine

# Clean the stock default so only our templated server remains.
RUN rm -f /etc/nginx/conf.d/default.conf

# envsubst template: the image rewrites ${PORT} at container start.
COPY default.conf.template /etc/nginx/templates/default.conf.template

# The built player (index.html at root, /Build engine payloads, /StreamingAssets asset tree).
COPY Build/ /usr/share/nginx/html/

# Only substitute PORT (leave nginx's own $uri/$host runtime vars untouched).
ENV NGINX_ENVSUBST_FILTER=PORT
ENV PORT=8080
EXPOSE 8080

# nginx:alpine's entrypoint runs envsubst over /etc/nginx/templates then launches nginx.
CMD ["nginx", "-g", "daemon off;"]
