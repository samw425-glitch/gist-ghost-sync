param(
  [Parameter(Mandatory=$false)]
  [string]$RootPath = "C:\\Users\\samwi\\Projects\\advanced-content-system",

  [Parameter(Mandatory=$false)]
  [string]$Output = "mesh.registry.json"
)

Write-Host "🔧 Generating mesh registry from hydra.manifest.json under: $RootPath" -ForegroundColor Cyan
$manifests = Get-ChildItem -Path $RootPath -Recurse -Filter "hydra.manifest.json" -ErrorAction SilentlyContinue

$services = @{}
foreach ($m in $manifests) {
  try {
    $json = Get-Content $m.FullName -Raw | ConvertFrom-Json
    if (-not $json.name -or -not $json.port) { continue }
    $name = [string]$json.name
    $port = [int]$json.port
    $health = "/health"
    if ($json.health -and $json.health.path) { $health = [string]$json.health.path }
    $services[$name] = @{ url = "http://localhost:$port"; health = $health }
  } catch {
    Write-Host "Skipping invalid manifest: $($m.FullName)" -ForegroundColor Yellow
  }
}

$registry = [ordered]@{
  version = 1
  generated_at = (Get-Date).ToString("s") + "Z"
  services = $services
}

$registry | ConvertTo-Json -Depth 4 | Out-File -FilePath $Output -Encoding UTF8
Write-Host "✅ Wrote mesh registry to $Output" -ForegroundColor Green
