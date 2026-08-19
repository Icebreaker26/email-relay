import crypto from 'crypto';
import { appendFileSync, statSync, writeFileSync, mkdirSync } from 'fs';
import express from 'express';
import nodemailer from 'nodemailer';
import dotenv from 'dotenv';
dotenv.config();

// ── Logging persistente a /app/logs/relay.log ────────────────
// El directorio lo monta Docker como volumen; fuera de Docker no existe
// pero el try/catch lo ignora silenciosamente.
const LOG_PATH = '/app/logs/relay.log';
const MAX_LOG  = 5 * 1024 * 1024; // 5 MB — rota en un solo archivo

try { mkdirSync('/app/logs', { recursive: true }); } catch { }

const writeLine = (level, args) => {
  const line = `${new Date().toISOString()} [${level}] ${args.join(' ')}\n`;
  try {
    let size = 0;
    try { size = statSync(LOG_PATH).size; } catch { }
    if (size > MAX_LOG) writeFileSync(LOG_PATH, line);
    else appendFileSync(LOG_PATH, line);
  } catch { }
};

const _log   = console.log.bind(console);
const _warn  = console.warn.bind(console);
const _error = console.error.bind(console);
console.log   = (...a) => { _log(...a);   writeLine('INFO',  a); };
console.warn  = (...a) => { _warn(...a);  writeLine('WARN',  a); };
console.error = (...a) => { _error(...a); writeLine('ERROR', a); };

const app  = express();
app.use(express.json({ limit: '512kb' }));

const {
  RELAY_SECRET,
  SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM,
  BACKEND_URL,
  PORT = 3099,
} = process.env;

if (!RELAY_SECRET || !SMTP_HOST || !SMTP_USER || !SMTP_PASS || !SMTP_FROM) {
  console.error('Faltan variables de entorno: RELAY_SECRET, SMTP_HOST, SMTP_USER, SMTP_PASS, SMTP_FROM');
  process.exit(1);
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Rate limiter global: máximo 500 emails por hora.
// Todo el tráfico llega desde cloudflared (localhost), por lo que req.ip
// siempre es 127.0.0.1 — el límite es efectivamente global, no por IP real.
const rateWindow = { count: 0, reset: Date.now() + 3_600_000 };
const rateLimit = (req, res, next) => {
  const now = Date.now();
  if (now > rateWindow.reset) { rateWindow.count = 0; rateWindow.reset = now + 3_600_000; }
  rateWindow.count++;
  if (rateWindow.count > 500) return res.status(429).json({ error: 'Demasiadas solicitudes' });
  next();
};

const transporter = nodemailer.createTransport({
  host:              SMTP_HOST,
  port:              Number(SMTP_PORT) || 465,
  secure:            (Number(SMTP_PORT) || 465) === 465,
  auth:              { user: SMTP_USER, pass: SMTP_PASS },
  connectionTimeout: 10000,
  socketTimeout:     15000,
});

app.post('/send-email', rateLimit, async (req, res) => {
  const auth    = req.headers['authorization'] ?? '';
  const given   = Buffer.from(auth.startsWith('Bearer ') ? auth.slice(7) : '');
  const expected = Buffer.from(RELAY_SECRET);
  const valid   = given.length === expected.length &&
                  crypto.timingSafeEqual(given, expected);
  if (!valid) return res.status(401).json({ error: 'No autorizado' });

  const { to, subject, html, text } = req.body;
  if (!to || !subject || !html) {
    return res.status(400).json({ error: 'Faltan campos: to, subject, html' });
  }
  if (!EMAIL_RE.test(to)) {
    return res.status(400).json({ error: 'Formato de email invalido' });
  }

  try {
    await transporter.sendMail({ from: SMTP_FROM, to, subject, html, text });
    res.json({ ok: true });
  } catch (err) {
    console.error('Error enviando email:', err.message);
    // No exponer detalles internos del SMTP al caller
    res.status(500).json({ error: 'Error al enviar el correo. Revisa los logs del relay.' });
  }
});

app.get('/health', (_, res) => res.json({ ok: true }));

app.listen(PORT, () => {
  console.log(`Email relay corriendo en puerto ${PORT}`);

  // Al arrancar, notifica al backend para que reintente emails pendientes
  if (BACKEND_URL && RELAY_SECRET) {
    setTimeout(async () => {
      try {
        const res = await fetch(`${BACKEND_URL}/api/monitor/reintentar-pendientes`, {
          method:  'POST',
          headers: { 'x-relay-secret': RELAY_SECRET },
          signal:  AbortSignal.timeout(15000),
        });
        const data = await res.json();
        if (data.procesados > 0) {
          console.log(`Reintento al arrancar: ${data.procesados} pendiente(s) procesado(s)`);
        }
      } catch (err) {
        console.warn('No se pudo contactar el backend al arrancar:', err.message);
      }
    }, 5000); // espera 5s para asegurar que el relay está listo
  }
});
