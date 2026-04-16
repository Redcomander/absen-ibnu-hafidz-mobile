param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'release'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$pubspec = Get-Content "$root\pubspec.yaml" -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([^\r\n]+)')
if (-not $versionMatch.Success) {
    throw 'Could not read version from pubspec.yaml'
}

$version = $versionMatch.Groups[1].Value.Trim()
$artifactName = "sistem-absensi-ibnu-hafidz-v$version-$Mode.apk"

flutter build apk --$Mode

$outputDir = Join-Path $root 'build\app\outputs\flutter-apk'
$sourceApk = Join-Path $outputDir "app-$Mode.apk"
if (-not (Test-Path $sourceApk)) {
    throw "Expected APK not found: $sourceApk"
}

$targetApk = Join-Path $outputDir $artifactName
Copy-Item $sourceApk $targetApk -Force
Write-Output "Created: $targetApk"
