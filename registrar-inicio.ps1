# registrar-inicio.ps1
# Registra start.ps1 como tarea de Windows que corre automaticamente al iniciar sesion.
# Tambien configura Docker Desktop para arrancar en segundo plano.
# Ejecutar UNA SOLA VEZ como Administrador.

$taskName  = "KernelEmailRelay"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script    = Join-Path $scriptDir "start.ps1"

if (-not (Test-Path $script)) {
    Write-Host "ERROR: No se encontro start.ps1 en $scriptDir" -ForegroundColor Red
    Read-Host "Presiona Enter para cerrar"
    exit 1
}

# ── Configurar Docker Desktop para arrancar en segundo plano ─
$dockerConfig = "$env:APPDATA\Docker\settings.json"
if (Test-Path $dockerConfig) {
    try {
        $cfg = Get-Content $dockerConfig -Raw | ConvertFrom-Json
        $cfg | Add-Member -NotePropertyName "autoStart"          -NotePropertyValue $true -Force
        $cfg | Add-Member -NotePropertyName "startOnBoot"        -NotePropertyValue $true -Force
        $cfg | Add-Member -NotePropertyName "openUIOnStartupIfLoggedIn" -NotePropertyValue $false -Force
        $cfg | ConvertTo-Json -Depth 10 | Set-Content $dockerConfig -Encoding utf8
        Write-Host "  OK  Docker Desktop configurado para arrancar en segundo plano" -ForegroundColor Green
    } catch {
        Write-Host "  !   No se pudo configurar Docker Desktop automaticamente." -ForegroundColor Yellow
        Write-Host "      Hazlo manualmente: Docker Desktop > Settings > General > Start when you log in" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  !   Docker Desktop no esta instalado o no se ha abierto aun." -ForegroundColor Yellow
    Write-Host "      Instalalo, abrelo una vez y vuelve a ejecutar este script." -ForegroundColor DarkGray
}

# Eliminar tarea previa si existe
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Silent" `
    -WorkingDirectory $scriptDir

# Se dispara al iniciar sesion del usuario actual
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 2) `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -Action   $action `
    -Trigger  $trigger `
    -Settings $settings `
    -RunLevel Highest `
    -Force | Out-Null

Write-Host ""
Write-Host "  Tarea '$taskName' registrada correctamente." -ForegroundColor Green
Write-Host ""
Write-Host "  Cada vez que inicies sesion en este PC el relay y el tunel" -ForegroundColor White
Write-Host "  arrancan solos en segundo plano." -ForegroundColor White
Write-Host ""
Write-Host "  Para verla: Programador de tareas > Biblioteca > $taskName" -ForegroundColor DarkGray
Write-Host "  Para borrarla: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false" -ForegroundColor DarkGray
Write-Host ""
Read-Host "Presiona Enter para cerrar"
