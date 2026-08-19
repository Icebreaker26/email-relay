# ============================================================
# start.ps1 — Arranca el relay, el tunel cloudflared y
#             actualiza RELAY_URL en Railway automaticamente
#
# Uso normal:    .\start.ps1
# Uso silencioso (Task Scheduler): .\start.ps1 -Silent
# ============================================================

param([switch]$Silent)

$RelayDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RelayPort = 3099
$TunnelLog = "$env:TEMP\cf-kernel-tunnel.log"

function Write-Step { param($n, $msg) Write-Host "`n[$n/3] $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg)     Write-Host "      OK  $msg" -ForegroundColor Green }
function Write-Warn { param($msg)     Write-Host "      !   $msg" -ForegroundColor Yellow }
function Write-Fail {
    param($msg)
    Write-Host "      ERR $msg" -ForegroundColor Red
    Read-Host "`nPresiona Enter para cerrar"
    exit 1
}

Write-Host ""
Write-Host "  KERNEL - Email Relay Launcher" -ForegroundColor White
Write-Host "  ================================" -ForegroundColor DarkGray

# ── Paso 1: Arrancar el relay ────────────────────────────────
Write-Step 1 "Iniciando servicio email-relay..."

$envFile = Join-Path $RelayDir ".env"
if (-not (Test-Path $envFile)) {
    Write-Fail "No se encontro .env en $RelayDir"
}

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Fail "Docker no encontrado. Instala Docker Desktop desde https://www.docker.com/products/docker-desktop"
}

# Verificar que Docker Desktop esta corriendo
try {
    docker info | Out-Null
} catch {
    Write-Fail "Docker no esta corriendo. Abre Docker Desktop y espera a que este listo."
}

# Detener contenedor previo si existe
docker stop email-relay 2>$null | Out-Null
docker rm   email-relay 2>$null | Out-Null

# Construir imagen (solo reconstruye si hubo cambios)
Write-Host "      Construyendo imagen Docker..." -NoNewline
docker build -t email-relay $RelayDir | Out-Null
Write-Host " listo" -ForegroundColor Green

# Arrancar contenedor aislado con auto-restart
docker run -d `
    --name email-relay `
    --env-file "$envFile" `
    -p "${RelayPort}:${RelayPort}" `
    --restart unless-stopped `
    email-relay | Out-Null

Write-OK "Relay corriendo en contenedor Docker aislado"

$relayOk = $false
Write-Host "      Esperando que el relay responda" -NoNewline
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    Write-Host "." -NoNewline
    try {
        $h = Invoke-RestMethod "http://localhost:$RelayPort/health" -TimeoutSec 2
        if ($h.ok) { $relayOk = $true; break }
    } catch { }
}
Write-Host ""

if (-not $relayOk) {
    Write-Fail "El relay no responde en puerto $RelayPort. Revisa que node este instalado y que .env tiene las variables correctas."
}
Write-OK "Relay en linea en http://localhost:$RelayPort"

# ── Paso 2: Arrancar tunel cloudflared ──────────────────────
Write-Step 2 "Iniciando tunel cloudflared..."

$cfCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cfCmd) {
    $cfPath = $cfCmd.Source
} else {
    $cfPath = $null
    $candidates = @(
        "$RelayDir\cloudflared.exe",
        "C:\cloudflared\cloudflared.exe",
        "$env:USERPROFILE\Downloads\cloudflared.exe",
        "$env:USERPROFILE\cloudflared.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $cfPath = $c; break }
    }
}

if (-not $cfPath) {
    Write-Fail "cloudflared no encontrado. Descargalo de https://github.com/cloudflare/cloudflared/releases y ponlo en $RelayDir"
}

Get-Process -Name cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if (Test-Path $TunnelLog) { Remove-Item $TunnelLog -Force }

Start-Process -FilePath $cfPath `
    -ArgumentList "tunnel --url http://localhost:$RelayPort" `
    -RedirectStandardError $TunnelLog `
    -WindowStyle Hidden

$tunnelUrl = $null
Write-Host "      Esperando URL del tunel" -NoNewline
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    Write-Host "." -NoNewline
    if (Test-Path $TunnelLog) {
        $raw = Get-Content $TunnelLog -Raw -ErrorAction SilentlyContinue
        if ($raw -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
            $tunnelUrl = $Matches[0]
            break
        }
    }
}
Write-Host ""

if (-not $tunnelUrl) {
    Write-Host "`n-- Log de cloudflared --" -ForegroundColor DarkGray
    Get-Content $TunnelLog -ErrorAction SilentlyContinue | Write-Host -ForegroundColor DarkGray
    Write-Fail "No se obtuvo la URL del tunel."
}
Write-OK "Tunel activo: $tunnelUrl"

# ── Paso 3: Actualizar Railway ───────────────────────────────
Write-Step 3 "Actualizando RELAY_URL en Railway..."

$railwayToken     = $null
$railwayServiceId = $null
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^RAILWAY_TOKEN\s*=\s*(.+)$')      { $railwayToken     = $Matches[1].Trim() }
    if ($_ -match '^RAILWAY_SERVICE_ID\s*=\s*(.+)$') { $railwayServiceId = $Matches[1].Trim() }
}

$updatedRailway = $false

if ($railwayToken -and $railwayServiceId) {
    $query = '{ "query": "mutation { variableUpsert(input: { serviceId: \"' + $railwayServiceId + '\", name: \"RELAY_URL\", value: \"' + $tunnelUrl + '\" }) }" }'
    try {
        $resp = Invoke-RestMethod `
            -Uri "https://backboard.railway.app/graphql/v2" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $railwayToken"; "Content-Type" = "application/json" } `
            -Body $query `
            -TimeoutSec 15

        if ($resp.data.variableUpsert) {
            Write-OK "RELAY_URL actualizado en Railway"
            $updatedRailway = $true
        } else {
            Write-Warn "Railway respondio pero no confirmo el cambio"
        }
    } catch {
        Write-Warn "Error llamando Railway API: $_"
    }
}

if (-not $updatedRailway) {
    $railwayCli = Get-Command railway -ErrorAction SilentlyContinue
    if ($railwayCli) {
        try {
            railway variables set "RELAY_URL=$tunnelUrl" | Out-Null
            Write-OK "RELAY_URL actualizado en Railway via CLI"
            $updatedRailway = $true
        } catch {
            Write-Warn "Railway CLI fallo: $_"
        }
    }
}

if (-not $updatedRailway) {
    Write-Warn "No se pudo actualizar Railway automaticamente."
    Write-Host ""
    Write-Host "      Agrega a .env del relay:" -ForegroundColor DarkGray
    Write-Host "        RAILWAY_TOKEN      = (Account Settings > Tokens)" -ForegroundColor DarkGray
    Write-Host "        RAILWAY_SERVICE_ID = (ID del servicio backend en Railway)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "      Por ahora pega esto en Railway > Variables:" -ForegroundColor Yellow
}

# ── Resumen ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  ================================" -ForegroundColor DarkGray
Write-Host "  Todo listo!" -ForegroundColor White
Write-Host ""
Write-Host "  RELAY_URL = $tunnelUrl" -ForegroundColor White

try { $tunnelUrl | Set-Clipboard; Write-Host "  (copiado al portapapeles)" -ForegroundColor DarkGray } catch { }

Write-Host ""
Write-Host "  Logs del relay : docker logs email-relay" -ForegroundColor DarkGray
Write-Host "  Log del tunel  : $TunnelLog" -ForegroundColor DarkGray
Write-Host ""

# ── Watchdog: reinicia el tunel si se cae el internet ───────
# Corre en segundo plano, verifica cada 2 minutos
$watchdogScript = {
    param($scriptPath)
    while ($true) {
        Start-Sleep -Seconds 120
        try {
            # Si el health del relay local falla, no hay nada que hacer
            $h = Invoke-RestMethod "http://localhost:3099/health" -TimeoutSec 5
            if (-not $h.ok) { continue }

            # Verificar que el tunel sigue vivo probando la URL publica
            $logFile = "$env:TEMP\cf-kernel-tunnel.log"
            $raw = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
            if ($raw -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
                $url = $Matches[0]
                try {
                    Invoke-RestMethod "$url/health" -TimeoutSec 10 | Out-Null
                    # Tunel OK — no hacer nada
                } catch {
                    # Tunel caido — relanzar el script completo
                    Write-Host "[watchdog] Tunel caido, reiniciando..." -ForegroundColor Yellow
                    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Silent"
                }
            }
        } catch { }
    }
}

Start-Job -ScriptBlock $watchdogScript -ArgumentList $MyInvocation.MyCommand.Definition | Out-Null

if (-not $Silent) {
    Read-Host "Presiona Enter para cerrar (relay y tunel siguen corriendo)"
}
