param(
  [switch]$Version
)

$ErrorActionPreference = 'Stop'

$serviceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$daguBin = Join-Path $serviceRoot 'vendor\dagu\dagu.exe'

if (-not (Test-Path $daguBin)) {
  throw "Dagu binary not found at $daguBin. Run scripts/package.ps1 to build the service artifact."
}

if ($Version) {
  & $daguBin version
  exit $LASTEXITCODE
}

$hostName = if ($env:DAGU_HOST) { $env:DAGU_HOST } else { '127.0.0.1' }
$port = if ($env:DAGU_PORT) { $env:DAGU_PORT } else { '18088' }
$homeDir = if ($env:DAGU_HOME) { $env:DAGU_HOME } else { Join-Path $serviceRoot 'data' }
$workflowDir = if ($env:DAGU_WORKFLOWS_DIR) { $env:DAGU_WORKFLOWS_DIR } else { Join-Path $serviceRoot 'workflows' }
$logDir = if ($env:DAGU_LOG_DIR) { $env:DAGU_LOG_DIR } else { Join-Path $serviceRoot 'logs' }

New-Item -ItemType Directory -Force -Path $homeDir, $workflowDir, $logDir | Out-Null

$env:DAGU_HOME = $homeDir
$env:DAGU_WORKFLOWS_DIR = $workflowDir
$env:DAGU_LOG_DIR = $logDir
$env:SERVICE_ROOT = $serviceRoot

& $daguBin start-all --host $hostName --port $port
exit $LASTEXITCODE
