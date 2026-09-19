FROM node:22-bookworm AS build
WORKDIR /app
COPY preview/package*.json ./
RUN npm ci
COPY preview/ ./
RUN npm run check
FROM nginx:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
