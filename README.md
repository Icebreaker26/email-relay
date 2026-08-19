# kernel — Email Relay

Servicio Express que actúa como puente entre Railway y el servidor SMTP de cPanel.

Railway no puede conectarse directamente a cPanel porque el firewall del hosting compartido bloquea IPs de datacenters en la nube. Este relay corre en una PC/servidor local de la oficina (que sí tiene acceso al SMTP) y se expone públicamente a través de un túnel Cloudflare.

```
Railway (backend) ──→ Cloudflare Tunnel ──→ PC oficina (relay) ──→ cPanel SMTP
```

---

## Archivos

| Archivo | Descripción |
|---|---|
| `server.js` | Servidor Express — recibe emails de Railway y los envía por SMTP |
| `start.ps1` | Arranca el relay, el túnel y actualiza `RELAY_URL` en Railway |
| `stop.ps1` | Detiene el relay y el túnel |
| `registrar-inicio.ps1` | Registra `start.ps1` como tarea de Windows (auto-arranque al iniciar sesión) |
| `.env` | Variables de entorno — **no subir a git** |

---

## Variables de entorno (`.env`)

```env
# Autenticación entre Railway y este relay
RELAY_SECRET=tu_secret_compartido

# SMTP de cPanel
SMTP_HOST=mail.tudominio.com
SMTP_PORT=465
SMTP_USER=correo@tudominio.com
SMTP_PASS=tu_password
SMTP_FROM="Cooperativa Progresemos <correo@tudominio.com>"

# Railway — para que start.ps1 actualice RELAY_URL automáticamente
RAILWAY_TOKEN=tu_token_de_railway
RAILWAY_SERVICE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Backend en Railway — para reintentar emails pendientes al arrancar
BACKEND_URL=https://tu-backend.up.railway.app

# Puerto local del relay (opcional, default: 3099)
PORT=3099
```

**Cómo obtener los valores de Railway:**
- `RAILWAY_TOKEN`: railway.app → avatar → Account Settings → Tokens → New Token
- `RAILWAY_SERVICE_ID`: railway.app → proyecto → servicio backend → Settings → Service ID

---

## Uso diario

### Arrancar

```powershell
.\start.ps1
```

El script:
1. Inicia el relay en `localhost:3099`
2. Lanza el túnel cloudflared y captura la URL pública
3. Actualiza `RELAY_URL` en Railway vía API
4. Copia la URL al portapapeles

### Detener

```powershell
.\stop.ps1
```

---

## Configurar auto-arranque en el servidor de oficina

Ejecutar **una sola vez** como Administrador:

```powershell
.\registrar-inicio.ps1
```

A partir de ahí, cada vez que el servidor enciende e inicia sesión, el relay y el túnel arrancan solos en segundo plano y Railway queda actualizado automáticamente.

Para quitar la tarea:

```powershell
Unregister-ScheduledTask -TaskName "KernelEmailRelay" -Confirm:$false
```

---

## Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| `POST` | `/send-email` | Envía un email. Requiere `Authorization: Bearer <RELAY_SECRET>`. Body: `{ to, subject, html, text }` |
| `GET` | `/health` | Verificación de estado. Devuelve `{ ok: true }` |

---

## Instalación en un servidor nuevo

```powershell
# 1. Instalar Node.js
winget install OpenJS.NodeJS.LTS

# 2. Instalar PM2 (gestor de procesos)
npm install -g pm2

# 3. Copiar esta carpeta al servidor e instalar dependencias
npm install

# 4. Crear el .env con las variables de arriba

# 5. Registrar la tarea de inicio (como Administrador)
.\registrar-inicio.ps1
```

---

## Diagnóstico

```powershell
# Ver logs del relay
pm2 logs email-relay

# Ver log del túnel cloudflared
cat $env:TEMP\cf-kernel-tunnel.log

# Probar el relay manualmente
Invoke-RestMethod http://localhost:3099/health
```
