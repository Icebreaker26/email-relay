import express from 'express';
import nodemailer from 'nodemailer';
import dotenv from 'dotenv';
dotenv.config();

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

// Rate limiter simple: máximo 60 emails por hora por IP
const ratemap = new Map();
const rateLimit = (req, res, next) => {
  const ip  = req.ip;
  const now = Date.now();
  const win = ratemap.get(ip) ?? { count: 0, reset: now + 3_600_000 };
  if (now > win.reset) { win.count = 0; win.reset = now + 3_600_000; }
  win.count++;
  ratemap.set(ip, win);
  if (win.count > 60) return res.status(429).json({ error: 'Demasiadas solicitudes' });
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
  const auth = req.headers['authorization'];
  if (!auth || auth !== `Bearer ${RELAY_SECRET}`) {
    return res.status(401).json({ error: 'No autorizado' });
  }

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
