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
if ($service.PSObject.Properties.Name -contains 'ports') {
  throw 'service.json still declares legacy top-level ports'
}
if ($service.PSObject.Properties.Name -contains 'urls') {
  throw 'service.json still declares legacy top-level urls'
}
$httpEndpoint = @($service.endpoints | Where-Object { $_.id -eq 'http' -and $_.kind -eq 'network' }) | Select-Object -First 1
if (-not $httpEndpoint) {
  throw 'service.json missing canonical http network endpoint'
}
if ($httpEndpoint.port.default -ne 18088 -or $httpEndpoint.protocol -ne 'http' -or $httpEndpoint.bind -ne '127.0.0.1') {
  throw 'service.json http endpoint does not preserve Dagu bind/port/protocol'
}
$uiEndpoint = @($service.endpoints | Where-Object { $_.id -eq 'ui' -and $_.kind -eq 'url' }) | Select-Object -First 1
$mcpEndpoint = @($service.endpoints | Where-Object { $_.id -eq 'mcp' -and $_.kind -eq 'url' }) | Select-Object -First 1
if (-not $uiEndpoint -or -not $mcpEndpoint) {
  throw 'service.json missing canonical Dagu URL endpoints'
}
if ($service.execconfig.env.DAGU_PORT -ne '${endpoint.http.port}') {
  throw 'service.json DAGU_PORT does not use endpoint selector'
}
if ($service.execconfig.globalenv.DAGU_URL -ne '${endpoint.ui.url}' -or $service.execconfig.globalenv.DAGU_MCP_URL -ne '${endpoint.mcp.url}') {
  throw 'service.json global URL exports do not use endpoint selectors'
}
$daguHealthcheck = @($service.execconfig.healthchecks | Where-Object { $_.id -eq 'ui' }) | Select-Object -First 1
if (-not $daguHealthcheck) {
  throw 'service.json missing canonical ui healthcheck'
}
if ($daguHealthcheck.url -ne '${endpoint.ui.url}') {
  throw 'service.json ui healthcheck does not use endpoint selector'
}
$manifestHealthcheckMatches = git -C $root ls-files '*service.json' |
  ForEach-Object { Join-Path $root $_ } |
  Select-String -Pattern '"healthcheck"\s*:' -List
if ($manifestHealthcheckMatches) {
  throw "singular healthcheck field remains in manifest: $($manifestHealthcheckMatches[0].Path)"
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
if ($LASTEXITCODE -ne 0) {
  throw "validate-dagu-secretref-fixtures.py failed with exit code $LASTEXITCODE"
}
& $python.Source (Join-Path $root 'scripts\validate-managed-workflow-sync.py')
if ($LASTEXITCODE -ne 0) {
  throw "validate-managed-workflow-sync.py failed with exit code $LASTEXITCODE"
}

Write-Host 'Dagu service tests passed (Windows)'
