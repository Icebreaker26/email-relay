# stop.ps1 — Detiene el relay y el tunel cloudflared

Write-Host ""
Write-Host "  KERNEL - Email Relay Stop" -ForegroundColor White
Write-Host "  ==========================" -ForegroundColor DarkGray

# Detener cloudflared
$cf = Get-Process -Name cloudflared -ErrorAction SilentlyContinue
if ($cf) {
    $cf | Stop-Process -Force
    Write-Host "  OK  Tunel cloudflared detenido" -ForegroundColor Green
} else {
    Write-Host "  --  cloudflared no estaba corriendo" -ForegroundColor DarkGray
}

# Detener relay (PM2 o node)
$pm2 = Get-Command pm2 -ErrorAction SilentlyContinue
if ($pm2) {
    try { pm2 stop email-relay | Out-Null; Write-Host "  OK  Relay (PM2) detenido" -ForegroundColor Green } catch { }
} else {
    $node = Get-Process -Name node -ErrorAction SilentlyContinue
    if ($node) {
        $node | Stop-Process -Force
        Write-Host "  OK  Relay (node) detenido" -ForegroundColor Green
    } else {
        Write-Host "  --  node no estaba corriendo" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  Servicios detenidos." -ForegroundColor White
Write-Host ""
Read-Host "Presiona Enter para cerrar"
