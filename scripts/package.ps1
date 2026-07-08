$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
$runtime = Join-Path $root 'runtime'
$cache = Join-Path $root '.tmp\dagu'
$staging = Join-Path $dist 'dagu-service-win32'
$zipPath = Join-Path $dist 'dagu-service-win32.zip'
$daguVersion = if ($env:DAGU_VERSION) { $env:DAGU_VERSION.TrimStart('v') } else { '2.10.1' }
$assetName = "dagu_${daguVersion}_windows_amd64.tar.gz"
$archivePath = Join-Path $cache $assetName
$extractPath = Join-Path $cache "windows_amd64_$daguVersion"
$downloadUrl = "https://github.com/dagucloud/dagu/releases/download/v$daguVersion/$assetName"

New-Item -ItemType Directory -Force -Path $dist, $cache | Out-Null

if (-not (Test-Path $archivePath)) {
  Write-Host "Downloading Dagu $daguVersion for Windows amd64"
  Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath
}

if (Test-Path $extractPath) { Remove-Item -Recurse -Force $extractPath }
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
tar -xzf $archivePath -C $extractPath

$daguBinary = Get-ChildItem -Path $extractPath -Recurse -Filter 'dagu.exe' | Select-Object -First 1
if (-not $daguBinary) {
  throw "Dagu executable not found in $archivePath"
}

if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $staging 'vendor\dagu') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $staging 'data'), (Join-Path $staging 'logs'), (Join-Path $staging 'workflows') | Out-Null

Copy-Item -Force (Join-Path $root 'service.json') (Join-Path $staging 'service.json')
Copy-Item -Recurse -Force (Join-Path $runtime 'win32') (Join-Path $staging 'runtime')
Copy-Item -Recurse -Force (Join-Path $root 'config') (Join-Path $staging 'config')
Copy-Item -Recurse -Force (Join-Path $root 'fixtures\dagu\workflows') (Join-Path $staging 'workflows\examples')
Copy-Item -Force $daguBinary.FullName (Join-Path $staging 'vendor\dagu\dagu.exe')

if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath
Write-Host "Created $zipPath"
