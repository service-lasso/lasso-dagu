$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

$required = @(
  (Join-Path $root 'service.json'),
  (Join-Path $root 'verify\service-harness.json'),
  (Join-Path $root 'runtime\win32\dagu-service.ps1'),
  (Join-Path $root 'docs\dagu-service-contract.md')
)

foreach ($path in $required) {
  if (-not (Test-Path $path)) {
    throw "Missing required file: $path"
  }
}

$service = Get-Content (Join-Path $root 'service.json') -Raw | ConvertFrom-Json
if ($service.id -ne 'dagu') {
  throw 'service.json id mismatch'
}
if ($service.execconfig.serviceport -ne 18088) {
  throw 'service.json Dagu port mismatch'
}
if ($service.meta.repository.url -notmatch 'lasso-dagu') {
  throw 'service.json repository still points at the template repo'
}
if (($service.meta.tags -join ',') -match 'template|example-service') {
  throw 'service.json still carries template/sample tags'
}

$contract = Get-Content (Join-Path $root 'verify\service-harness.json') -Raw | ConvertFrom-Json
if ($contract.serviceId -ne 'dagu') {
  throw 'service-harness.json serviceId mismatch'
}

$zipPath = Join-Path $root 'dist\dagu-service-win32.zip'
if (Test-Path $zipPath) {
  $extract = Join-Path $root 'output\test\dagu-service-win32'
  if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
  New-Item -ItemType Directory -Force -Path $extract | Out-Null
  Expand-Archive -Path $zipPath -DestinationPath $extract -Force
  $runtime = Join-Path $extract 'runtime\dagu-service.ps1'
  if (-not (Test-Path $runtime)) {
    throw 'packaged Dagu launcher missing from Windows artifact'
  }
  $versionOutput = & $runtime -Version | Out-String
  if ($versionOutput -notmatch '\d+\.\d+\.\d+') {
    throw 'packaged Dagu launcher did not report a Dagu version'
  }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
  $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if (-not $python) {
  throw 'python/python3 is required for Dagu secret-ref fixture validation'
}
& $python.Source (Join-Path $root 'scripts\validate-dagu-secretref-fixtures.py')

Write-Host 'Dagu service tests passed (Windows)'
