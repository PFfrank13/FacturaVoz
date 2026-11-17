# Fase 5: crear artefactos de distribución EXCLUSIVAMENTE en el equipo con la llave privada.
# Windows PowerShell 5.1+. No se cargan secretos a GitHub ni se despliega nada automáticamente.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DefinesFile,
    [switch]$InstallOnDevice
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Run-Tool([string]$Name, [string[]]$Arguments) {
    & $Name @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falló $Name (código $LASTEXITCODE). Se bloqueó la distribución."
    }
}
$project = (Resolve-Path (Join-Path $PSScriptRoot '../../app')).Path
$defines = (Resolve-Path $DefinesFile).Path
$preflight = (Join-Path $PSScriptRoot 'preflight.py')
$signing = Join-Path $HOME 'FacturaVoz-Signing'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter no está instalado o disponible en PATH."
}
if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 $preflight --release --project $project --defines $defines --signing-dir $signing
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    & python $preflight --release --project $project --defines $defines --signing-dir $signing
} else {
    throw "Python 3 es obligatorio para el preflight de firma y defines."
}
if ($LASTEXITCODE -ne 0) { throw "Release bloqueado: preflight falló." }

$androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $env:ANDROID_HOME }
if (-not $androidSdk -or -not (Test-Path $androidSdk)) {
    throw "Configura ANDROID_SDK_ROOT o ANDROID_HOME antes de compilar."
}
$buildTools = @(Get-ChildItem (Join-Path $androidSdk 'build-tools') -Directory |
    Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending)
if ($buildTools.Count -eq 0) { throw "Faltan Android SDK Build Tools." }
$apksigner = Join-Path $buildTools[0].FullName 'apksigner.bat'
if (-not (Test-Path $apksigner)) { throw "No se encontró apksigner.bat en Android SDK Build Tools." }
if (-not (Get-Command jarsigner -ErrorAction SilentlyContinue)) {
    throw "Instala un JDK con jarsigner y agrégalo a PATH."
}

Push-Location $project
try {
    Run-Tool 'flutter' @('pub', 'get')
    Run-Tool 'flutter' @('analyze')
    Run-Tool 'flutter' @('test')
    Run-Tool 'flutter' @('build', 'apk', '--release', "--dart-define-from-file=$defines")
    Run-Tool 'flutter' @('build', 'appbundle', '--release', "--dart-define-from-file=$defines")
} finally {
    Pop-Location
}

$apk = Join-Path $project 'build/app/outputs/flutter-apk/app-release.apk'
$aab = Join-Path $project 'build/app/outputs/bundle/release/app-release.aab'
foreach ($artifact in @($apk, $aab)) {
    if (-not (Test-Path $artifact)) { throw "Falta el artefacto esperado: $artifact" }
    if ((Get-Item $artifact).Length -le 0) { throw "Artefacto de distribución vacío." }
}
# Comprobar firmas usando herramientas oficiales. No se pasa la contraseña a comandos.
Run-Tool $apksigner @('verify', '--verbose', '--print-certs', $apk)
$aabVerify = & jarsigner '-J-Duser.language=en' '-verify' $aab 2>&1
if ($LASTEXITCODE -ne 0 -or (($aabVerify -join ' ') -notmatch 'jar verified')) {
    throw "La firma JAR del Android App Bundle no pudo validarse."
}

$versionLine = Get-Content (Join-Path $project 'pubspec.yaml') |
    Where-Object { $_ -match '^version:\s*\d+\.\d+\.\d+\+\d+' } | Select-Object -First 1
if (-not $versionLine) { throw "Versión de publicación no disponible." }
$version = ($versionLine -split ':', 2)[1].Trim()
$releaseManifest = [ordered]@{
    generated_utc = [DateTime]::UtcNow.ToString('o')
    version = $version
    package = 'dev.solvexsoftware.facturavoz'
    apk_sha256 = (Get-FileHash $apk -Algorithm SHA256).Hash
    aab_sha256 = (Get-FileHash $aab -Algorithm SHA256).Hash
    apk_signature_verified = $true
    aab_signature_verified = $true
    physical_tests_complete = $false
    sunat_live_verified = $false
}
$manifestPath = Join-Path $project 'build/fase5-release-evidence.json'
$releaseManifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
Write-Host "OK: APK y AAB firmados y firmas comprobadas. Evidencia: $manifestPath"

if ($InstallOnDevice) {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        throw "adb no disponible; instalación física pendiente."
    }
    $connected = @(& adb devices | Select-String '\sdevice$')
    if ($connected.Count -ne 1) {
        throw "Se requiere exactamente un teléfono Android autorizado por ADB."
    }
    Run-Tool 'adb' @('install', '-r', $apk)
    Run-Tool 'adb' @('shell', 'monkey', '-p', 'dev.solvexsoftware.facturavoz',
                      '-c', 'android.intent.category.LAUNCHER', '1')
    Write-Host "Instalación y apertura verificadas en un teléfono. El QA físico y SUNAT siguen pendientes."
}
