FROM node:20-alpine

# Usuario sin privilegios — si alguien compromete el proceso,
# no tiene acceso a nada fuera del contenedor
RUN addgroup -S relay && adduser -S relay -G relay

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY server.js ./

# Directorio de logs — el volumen se monta aquí en producción
RUN mkdir -p /app/logs && chown relay:relay /app/logs

USER relay

EXPOSE 3099

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3099/health || exit 1

CMD ["node", "server.js"]
