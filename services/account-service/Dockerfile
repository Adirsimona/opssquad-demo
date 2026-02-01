FROM node:20-alpine

RUN apk add --no-cache curl bash

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3002

ENTRYPOINT ["/entrypoint.sh"]
