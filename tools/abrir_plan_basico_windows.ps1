#Requires -Version 5.1
<#
FacturaVoz Plan Basico - Windows / Android Studio.
Creates a detached WORKTREE of GitHub main, preserving the codex/facturavoz-evolucion
checkout, all of its local files, and its Git history. Does not touch Hub or production data.
Run from the Android Studio terminal inside the existing app directory.
#>
param(
  [switch]$PrepareOnly,
  [string]$DeviceId = ""
)
$ErrorActionPreference = 'Continue' # We explicitly verify native git/flutter exit codes.
function Assert-Exit([string]$Operation) {
  if ($LASTEXITCODE -ne 0) { throw "$Operation failed (exit $LASTEXITCODE)." }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'Git no esta disponible en PowerShell. Abre el terminal de Android Studio con Git configurado.'
}
$repoRoot = (& git rev-parse --show-toplevel 2>$null)
Assert-Exit 'git rev-parse'
$repoRoot = [System.IO.Path]::GetFullPath(($repoRoot | Select-Object -First 1).Trim())
$origin = (& git -C $repoRoot remote get-url origin)
Assert-Exit 'git remote get-url origin'
if ($origin -notmatch '(?i)PFfrank13/FacturaVoz(\.git)?$') {
  throw 'La carpeta actual no es el repositorio PFfrank13/FacturaVoz. No se modifico nada.'
}

Write-Host '[1/5] Obteniendo main, SIN modificar tu rama codex...' -ForegroundColor Cyan
& git -C $repoRoot fetch --quiet origin main
Assert-Exit 'git fetch origin main'

$parent = Split-Path -Path $repoRoot -Parent
$previewRoot = Join-Path $parent 'FacturaVoz-PlanBasico'
if (-not (Test-Path -LiteralPath $previewRoot)) {
  Write-Host '[2/5] Creando copia de trabajo independiente...' -ForegroundColor Cyan
  & git -C $repoRoot worktree add --quiet --detach $previewRoot origin/main
  Assert-Exit 'git worktree add'
} else {
  $worktrees = (& git -C $repoRoot worktree list --porcelain)
  Assert-Exit 'git worktree list'
  $expected = 'worktree ' + ($previewRoot -replace '\\','/')
  $registered = @($worktrees | Where-Object { ($_ -replace '\\','/') -eq $expected }).Count -gt 0
  if (-not $registered) {
    throw "La ruta $previewRoot ya existe y NO es un worktree de este repositorio. No se tocara."
  }
  $dirty = @(& git -C $previewRoot status --porcelain)
  Assert-Exit 'git status'
  if ($dirty.Count -gt 0 -and ($dirty -join '').Trim().Length -gt 0) {
    throw "Hay cambios propios en $previewRoot. Guardalos antes de actualizar esta vista previa."
  }
  Write-Host '[2/5] Actualizando solamente la copia de trabajo del Plan Basico...' -ForegroundColor Cyan
  & git -C $previewRoot switch --quiet --detach origin/main
  Assert-Exit 'git switch --detach origin/main'
}

$appPath = Join-Path $previewRoot 'app'
$defines = Join-Path $appPath 'dart_defines.json'
if (-not (Test-Path -LiteralPath $defines)) {
  $originalDefines = Join-Path (Join-Path $repoRoot 'app') 'dart_defines.json'
  if (Test-Path -LiteralPath $originalDefines) {
    Copy-Item -LiteralPath $originalDefines -Destination $defines
    Write-Host '[3/5] Se copio la configuracion publica desde la instalacion anterior.' -ForegroundColor Green
  } else {
    Write-Host '[3/5] Falta un dart_defines.json local; preparare uno sin tocar la configuracion anterior.' -ForegroundColor Yellow
    $key = $env:SUPABASE_ANON_KEY
    if ([string]::IsNullOrWhiteSpace($key)) {
      Write-Host 'Necesitas la clave publica anon o sb_publishable de tu proyecto Supabase.' -ForegroundColor Yellow
      Write-Host 'Supabase > Project Settings > API Keys. Nunca uses service_role.' -ForegroundColor Yellow
      $key = Read-Host 'Clave PUBLICABLE de Supabase'
    }
    if ([string]::IsNullOrWhiteSpace($key) -or $key.Trim().Length -lt 20) {
      throw 'La clave PUBLICABLE esta vacia o es demasiado corta.'
    }
    $values = @{
      SUPABASE_URL = 'https://qzcpeipjlskyazrrelqu.supabase.co'
      SUPABASE_ANON_KEY = $key.Trim()
      API_BASE_URL = 'https://factura-voz-two.vercel.app'
    }
    $json = ConvertTo-Json -InputObject $values -Depth 4
    [System.IO.File]::WriteAllText($defines, $json, ([System.Text.UTF8Encoding]::new($false)))
  }
}
try {
  $config = Get-Content -LiteralPath $defines -Raw | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($config.SUPABASE_URL) -or
      [string]::IsNullOrWhiteSpace($config.SUPABASE_ANON_KEY) -or
      [string]::IsNullOrWhiteSpace($config.API_BASE_URL)) {
    throw 'Faltan SUPABASE_URL, SUPABASE_ANON_KEY o API_BASE_URL.'
  }
  if ($config.SUPABASE_URL -ne 'https://qzcpeipjlskyazrrelqu.supabase.co') {
    throw 'La configuracion apunta a otro Supabase. Detenido para evitar abrir otra empresa accidentalmente.'
  }
} catch {
  throw "dart_defines.json invalido: $($_.Exception.Message)"
}

Write-Host '[4/5] Comprobando Flutter y resolviendo dependencias...' -ForegroundColor Cyan
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "La copia ya esta creada en: $appPath" -ForegroundColor Yellow
  throw 'Flutter no aparece en PATH. Configuralo en Android Studio/PowerShell antes de ejecutar.'
}
Push-Location $appPath
try {
  & flutter pub get
  Assert-Exit 'flutter pub get'
  Write-Host "Abre esta nueva carpeta en Android Studio: $appPath" -ForegroundColor Green
  if ($PrepareOnly) {
    Write-Host 'Preparacion completada. No se inicio el emulador por -PrepareOnly.' -ForegroundColor Green
    exit 0
  }

  if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    $rawDevices = & flutter devices --machine
    Assert-Exit 'flutter devices --machine'
    # ConvertFrom-Json on Windows PowerShell 5.1 may return a JSON array as
    # a single object. Enumerate it explicitly, never use .id on an array.
    $deviceList = ConvertFrom-Json -InputObject ($rawDevices -join "`n")
    foreach ($device in $deviceList) {
      if (($device.targetPlatform -like 'android*') -and
          ($device.id -match '^emulator-[0-9]+
  Write-Host "[5/5] Instalando y ejecutando FacturaVoz main en $DeviceId..." -ForegroundColor Green
  Write-Host 'Deten antes cualquier Flutter Run anterior para evitar dos sesiones de depuracion.' -ForegroundColor Yellow
  & flutter run -d $DeviceId --debug "--dart-define-from-file=$defines"
  Assert-Exit 'flutter run'
} finally {
  Pop-Location
}
) -and
          ($device.isSupported -ne $false)) {
        $DeviceId = [string]$device.id
        break
      }
    }
    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
      foreach ($device in $deviceList) {
        if (($device.targetPlatform -like 'android*') -and
            ($device.isSupported -ne $false)) {
          $DeviceId = [string]$device.id
          break
        }
      }
    }
    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
      throw 'No hay emulador Android activo. Abre Medium Phone API 37 desde Android Studio y ejecuta de nuevo.'
    }
  }
  if ([string]::IsNullOrWhiteSpace($DeviceId) -or $DeviceId -match '\s') {
    throw 'DeviceId invalido: especifica un unico emulador, como emulator-5554.'
  }

  Write-Host "[5/5] Instalando y ejecutando FacturaVoz main en $DeviceId..." -ForegroundColor Green
  Write-Host 'Deten antes cualquier Flutter Run anterior para evitar dos sesiones de depuracion.' -ForegroundColor Yellow
  & flutter run -d $DeviceId --debug "--dart-define-from-file=$defines"
  Assert-Exit 'flutter run'
} finally {
  Pop-Location
}
