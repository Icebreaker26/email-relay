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

# Detener contenedor Docker
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerCmd) {
    $running = docker ps -q --filter "name=email-relay" 2>$null
    if ($running) {
        docker stop email-relay | Out-Null
        docker rm   email-relay | Out-Null
        Write-Host "  OK  Contenedor Docker detenido" -ForegroundColor Green
    } else {
        Write-Host "  --  Contenedor no estaba corriendo" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  --  Docker no encontrado" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Servicios detenidos." -ForegroundColor White
Write-Host ""
Read-Host "Presiona Enter para cerrar"
