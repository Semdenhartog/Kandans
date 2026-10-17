# RunWise - eenmalige installatie van het Android-project.
# Uitvoeren in PowerShell vanuit deze map:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "1/5  Android-projectbestanden aanmaken..." -ForegroundColor Green
flutter create --org nl.runwise --project-name runwise --platforms android .

Write-Host "2/5  Rechten (internet en locatie) toevoegen aan AndroidManifest.xml..." -ForegroundColor Green
$manifest = Join-Path $PSScriptRoot "android\app\src\main\AndroidManifest.xml"
$xml = [IO.File]::ReadAllText($manifest)
if ($xml -notmatch "android.permission.INTERNET") {
    $perms = @"
<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <application
"@
    $xml = $xml -replace "<application", $perms.TrimEnd()
}
if ($xml -notmatch "android.intent.action.VIEW") {
    $queries = @"
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
    </queries>
</manifest>
"@
    $xml = $xml -replace "</manifest>", $queries
}
$xml = $xml -replace 'android:label="runwise"', 'android:label="RunWise"'
[IO.File]::WriteAllText($manifest, $xml)

Write-Host "3/5  Pakketten downloaden..." -ForegroundColor Green
flutter pub get

Write-Host "4/5  Code controleren..." -ForegroundColor Green
flutter analyze | Tee-Object -FilePath analyze.txt

Write-Host "5/5  Tests draaien..." -ForegroundColor Green
flutter test | Tee-Object -FilePath tests.txt

if (-not (Test-Path "config.json")) {
    Copy-Item "config.example.json" "config.json"
    Write-Host "config.json aangemaakt: vul hierin je Supabase-URL en anon key in." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Klaar. Stuur analyze.txt en tests.txt naar Claude als er fouten in staan." -ForegroundColor Green
