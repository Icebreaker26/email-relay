# Email Relay

Servicio que permite a aplicaciones en la nube (Railway, Render, Heroku, etc.) enviar emails a través de un servidor SMTP de hosting compartido (cPanel, Plesk, etc.), que normalmente bloquea conexiones desde IPs de datacenter.

```
App en la nube ──→ Cloudflare Tunnel ──→ Este servicio (PC/servidor local) ──→ SMTP cPanel
```

El servicio corre en una PC o servidor de oficina que sí tiene acceso al SMTP, y se expone públicamente a través de un túnel Cloudflare gratuito. Cuando se reinicia, actualiza automáticamente la URL del túnel en Railway sin intervención manual.

---

## Características

- **Aislado en Docker** — corre en un contenedor con usuario sin privilegios; si alguien comprometiera el servicio, no tendría acceso al sistema del host
- **Auto-arranque** — inicia solo cuando el PC enciende, sin intervención manual
- **Auto-recuperación** — un watchdog detecta caídas de internet y reinicia el túnel automáticamente
- **Cola de reenvío** — los emails que fallaron mientras el servicio estuvo apagado se reenvían solos al volver a arrancar
- **Rate limiting** — máximo 500 emails por hora por IP para prevenir abuso
- **Genérico** — cualquier proyecto puede usarlo, no está atado a una aplicación específica

---

## Requisitos

- Windows 10/11
- [Docker Desktop](https://www.docker.com/products/docker-desktop) instalado y abierto al menos una vez
- Acceso a internet
- Credenciales SMTP de tu hosting (cPanel, Plesk, etc.)

---

## Instalación

### 1. Clonar o copiar la carpeta

Descarga o clona este repositorio en el PC donde correrá el servicio. Por ejemplo:

```
C:\relay\
```

### 2. Crear el archivo `.env`

Copia `.env.example` como `.env` y completa los valores:

```
C:\relay\.env
```

```env
# Clave secreta compartida entre tu app en la nube y este relay.
# Generar con: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
RELAY_SECRET=

# Credenciales SMTP de tu hosting
SMTP_HOST=mail.tudominio.com
SMTP_PORT=465
SMTP_USER=correo@tudominio.com
SMTP_PASS=tu_contraseña_smtp
SMTP_FROM="Nombre Remitente <correo@tudominio.com>"

# Railway — para actualizar RELAY_URL automaticamente al arrancar
# Token: railway.app > avatar > Account Settings > Tokens > New Token
RAILWAY_TOKEN=
# Service ID: railway.app > proyecto > servicio > Settings > Service ID
RAILWAY_SERVICE_ID=

# URL de tu backend en Railway
BACKEND_URL=https://tu-backend.up.railway.app

# Puerto local del relay (no cambiar salvo conflicto)
PORT=3099
```

> **Importante:** `.env` nunca se sube a git. Contiene tus credenciales.

### 3. Instalar Docker Desktop

Descarga e instala Docker Desktop desde [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop).

Ábrelo una vez para que termine la configuración inicial. Puedes cerrarlo después — el siguiente paso lo configurará para que arranque solo.

### 4. Ejecutar el instalador

Abre PowerShell **como Administrador**, navega a la carpeta del proyecto y ejecuta:

```powershell
.\registrar-inicio.ps1
```

Este script hace automáticamente:
- Descarga `cloudflared.exe` si no está presente
- Configura Docker Desktop para arrancar en segundo plano al iniciar sesión
- Registra una tarea de Windows que lanza el servicio automáticamente al encender el PC

### 5. Reiniciar el PC

Al volver a encender, el servicio arranca solo. No se requiere ninguna acción adicional.

---

## Variables en tu app (Railway)

Agrega estas variables de entorno en el servicio de tu backend en Railway:

| Variable | Valor |
|---|---|
| `RELAY_URL` | Se actualiza automáticamente al arrancar |
| `RELAY_SECRET` | El mismo valor que pusiste en `.env` |

`RELAY_URL` la gestiona el script — no necesitas tocarla manualmente.

---

## Uso diario

### Arrancar manualmente

Abre PowerShell en la carpeta del proyecto:

```powershell
.\start.ps1
```

### Detener manualmente

```powershell
.\stop.ps1
```

---

## Cómo funciona el arranque automático

Cuando el PC enciende e inicia sesión ocurre esto en orden:

1. Docker Desktop arranca en segundo plano
2. Windows ejecuta `start.ps1 -Silent` automáticamente
3. El script levanta el contenedor Docker con el relay
4. Lanza el túnel cloudflared y captura la URL pública
5. Llama la API de Railway y actualiza `RELAY_URL` con la nueva URL
6. Notifica al backend para que reenvíe emails que hayan fallado mientras el servicio estuvo apagado
7. Un watchdog queda corriendo en segundo plano verificando el túnel cada 2 minutos

### Recuperación ante caída de internet

Si el internet se cae y vuelve:

1. El watchdog detecta que el túnel no responde
2. Reinicia el servicio automáticamente
3. Crea un nuevo túnel con URL nueva
4. Actualiza Railway con la nueva URL

Sin intervención manual.

---

## Endpoints

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| `POST` | `/send-email` | `Bearer <RELAY_SECRET>` | Envía un email |
| `GET` | `/health` | Ninguna | Verifica que el servicio está vivo |

**Body de `/send-email`:**

```json
{
  "to": "destinatario@ejemplo.com",
  "subject": "Asunto del correo",
  "html": "<p>Cuerpo en HTML</p>",
  "text": "Cuerpo en texto plano (opcional)"
}
```

---

## Integración en tu backend (Node.js)

```js
const sendViaRelay = async (to, subject, html, text) => {
  const res = await fetch(process.env.RELAY_URL + '/send-email', {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${process.env.RELAY_SECRET}`,
    },
    body:   JSON.stringify({ to, subject, html, text }),
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error ?? `Relay error ${res.status}`);
  }
};
```

---

## Diagnóstico

```powershell
# Ver logs del relay en tiempo real
docker logs -f email-relay

# Ver log persistente (sobrevive reinicios del contenedor)
docker run --rm -v email-relay-logs:/logs alpine cat /logs/relay.log

# Ver log del túnel cloudflared
cat $env:TEMP\cf-kernel-tunnel.log

# Probar que el relay responde localmente
Invoke-RestMethod http://localhost:3099/health

# Ver tareas programadas de Windows
Get-ScheduledTask -TaskName "KernelEmailRelay"

# Eliminar la tarea de inicio
Unregister-ScheduledTask -TaskName "KernelEmailRelay" -Confirm:$false

# Forzar reconstrucción de la imagen Docker (después de cambiar server.js)
docker rmi email-relay
.\start.ps1
```

> **Logs persistentes:** el relay escribe en `/app/logs/relay.log` dentro del contenedor.
> Ese directorio está montado en un volumen Docker (`email-relay-logs`) que sobrevive reinicios y
> recreaciones del contenedor. El archivo rota automáticamente al superar los 5 MB.

---

## Seguridad

- El relay corre en un **contenedor Docker con usuario sin privilegios** (`relay`) — acceso mínimo al sistema
- El `.env` se pasa como `--env-file` y **nunca entra a la imagen Docker**
- **Rate limiting**: máximo 500 emails/hora por IP
- **Validación de email**: el campo `to` se valida antes de enviar
- **Errores SMTP ocultos**: los detalles internos solo aparecen en los logs del relay, nunca en la respuesta HTTP
- La URL del túnel cambia en cada reinicio — la oscuridad suma una capa adicional
