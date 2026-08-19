import express from 'express';
import nodemailer from 'nodemailer';
import dotenv from 'dotenv';
dotenv.config();

const app  = express();
app.use(express.json());

const {
  RELAY_SECRET,
  SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM,
  BACKEND_URL,
  PORT = 3099,
} = process.env;

if (!RELAY_SECRET || !SMTP_HOST || !SMTP_USER || !SMTP_PASS) {
  console.error('Faltan variables de entorno: RELAY_SECRET, SMTP_HOST, SMTP_USER, SMTP_PASS');
  process.exit(1);
}

const transporter = nodemailer.createTransport({
  host:              SMTP_HOST,
  port:              Number(SMTP_PORT) || 465,
  secure:            (Number(SMTP_PORT) || 465) === 465,
  auth:              { user: SMTP_USER, pass: SMTP_PASS },
  connectionTimeout: 10000,
  socketTimeout:     15000,
});

app.post('/send-email', async (req, res) => {
  const auth = req.headers['authorization'];
  if (!auth || auth !== `Bearer ${RELAY_SECRET}`) {
    return res.status(401).json({ error: 'No autorizado' });
  }

  const { to, subject, html, text } = req.body;
  if (!to || !subject || !html) {
    return res.status(400).json({ error: 'Faltan campos: to, subject, html' });
  }

  try {
    await transporter.sendMail({ from: SMTP_FROM, to, subject, html, text });
    res.json({ ok: true });
  } catch (err) {
    console.error('Error enviando email:', err.message);
    res.status(500).json({ error: err.message });
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
