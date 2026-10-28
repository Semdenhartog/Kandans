# Kadans - eenmalig een ondertekeningssleutel (uploadsleutel) maken voor de Play Store.
#
# Uitvoeren in PowerShell vanuit deze map:
#   powershell -ExecutionPolicy Bypass -File .\maak-sleutel.ps1
#
# Het script maakt:
#   - kadans-upload-key.jks        de sleutel zelf (BEWAREN, bijv. op een USB-stick of in je wachtwoordmanager)
#   - kadans-github-geheimen.txt   de 4 waarden die je in GitHub zet (daarna verwijderen!)
# Beide bestanden komen NIET in git (staan in .gitignore).

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$keystore = Join-Path $PSScriptRoot "kadans-upload-key.jks"
$output = Join-Path $PSScriptRoot "kadans-github-geheimen.txt"
$alias = "upload"

if (Test-Path $keystore) {
    Write-Host "Er bestaat al een sleutel ($keystore). Gebruik die, of verwijder hem eerst bewust." -ForegroundColor Yellow
    exit 1
}

# keytool zit bij Android Studio (Java). Zoek hem op de gebruikelijke plekken.
$candidates = @(
    "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
    "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe",
    "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe"
)
$keytool = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $keytool) {
    $cmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($cmd) { $keytool = $cmd.Source }
}
if (-not $keytool) {
    Write-Host "keytool niet gevonden. Installeer Android Studio (https://developer.android.com/studio) en probeer opnieuw." -ForegroundColor Red
    exit 1
}

# Sterk willekeurig wachtwoord (alleen letters en cijfers, dat voorkomt problemen).
$chars = [char[]]"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 32
$rng.GetBytes($bytes)
$password = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })

Write-Host "Sleutel maken..." -ForegroundColor Green
& $keytool -genkeypair -v `
    -keystore $keystore `
    -storetype JKS `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -alias $alias `
    -storepass $password -keypass $password `
    -dname "CN=Kadans, O=Kadans, C=NL" | Out-Null

$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))

@"
Zet deze 4 geheimen in GitHub:
  github.com/Semdenhartog/Kandans -> Settings -> Secrets and variables -> Actions -> New repository secret

Naam: ANDROID_KEYSTORE_BASE64
"@ | Set-Content $output

Write-Host "Sleutel en instructies gemaakt: $keystore en $output" -ForegroundColor Green
