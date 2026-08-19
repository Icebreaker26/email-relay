FROM node:20-alpine

# Usuario sin privilegios — si alguien compromete el proceso,
# no tiene acceso a nada fuera del contenedor
RUN addgroup -S relay && adduser -S relay -G relay

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY server.js ./

USER relay

EXPOSE 3099

CMD ["node", "server.js"]
