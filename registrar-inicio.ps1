# registrar-inicio.ps1
# Registra start.ps1 como tarea de Windows que corre automaticamente al iniciar sesion.
# Ejecutar UNA SOLA VEZ como Administrador.

$taskName  = "KernelEmailRelay"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script    = Join-Path $scriptDir "start.ps1"

if (-not (Test-Path $script)) {
    Write-Host "ERROR: No se encontro start.ps1 en $scriptDir" -ForegroundColor Red
    Read-Host "Presiona Enter para cerrar"
    exit 1
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
