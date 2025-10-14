param(
  [Parameter(Mandatory=$false)]
  [string]$RootPath = "C:\\Users\\samwi\\Projects\\advanced-content-system",

  [Parameter(Mandatory=$false)]
  [string]$ReposFile,

  [Parameter(Mandatory=$false)]
  [string]$Output = "mesh.registry.json"
)

function Decode-Base64String {
  param([string]$Encoded)
  $bytes = [System.Convert]::FromBase64String($Encoded)
  return [System.Text.Encoding]::UTF8.GetString($bytes)
}

$services = @{}

if ($ReposFile -and (Test-Path $ReposFile)) {
  Write-Host "🔧 Generating mesh registry from repos listed in: $ReposFile" -ForegroundColor Cyan
  $repos = Get-Content -Path $ReposFile | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }

  foreach ($repo in $repos) {
    try {
      # Fetch hydra.manifest.json via GitHub API (using gh if available)
      $ownerRepo = $repo
      $apiPath = "repos/$ownerRepo/contents/hydra.manifest.json"
      $contentJson = $null
      if (Get-Command gh -ErrorAction SilentlyContinue) {
        $contentRaw = gh api $apiPath 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $contentRaw) { Write-Host "No manifest in $ownerRepo" -ForegroundColor DarkYellow; continue }
        $contentJson = $contentRaw | ConvertFrom-Json
      } else {
        $token = $env:GH_TOKEN; if (-not $token) { $token = $env:GITHUB_TOKEN }
        $headers = @{}
        if ($token) { $headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'mesh-generator' } }
        $url = "https://api.github.com/$apiPath"
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction SilentlyContinue
        if (-not $resp) { Write-Host "No manifest in $ownerRepo" -ForegroundColor DarkYellow; continue }
        $contentJson = $resp
      }
      if (-not $contentJson.content) { Write-Host "Missing content for $ownerRepo" -ForegroundColor DarkYellow; continue }
      $decoded = Decode-Base64String ($contentJson.content -replace "\n","")
      $json = $decoded | ConvertFrom-Json
      if (-not $json.name -or -not $json.port) { Write-Host "Invalid manifest in $ownerRepo" -ForegroundColor DarkYellow; continue }
      $name = [string]$json.name
      $port = [int]$json.port
      $health = "/health"
      if ($json.health -and $json.health.path) { $health = [string]$json.health.path }
      $services[$name] = @{ url = "http://localhost:$port"; health = $health }
      Write-Host "✔ Found $name on port $port from $ownerRepo" -ForegroundColor Green
    } catch {
      Write-Host "Skipping repo $repo due to error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
} else {
  Write-Host "🔧 Generating mesh registry by scanning local manifests under: $RootPath" -ForegroundColor Cyan
  $manifests = Get-ChildItem -Path $RootPath -Recurse -Filter "hydra.manifest.json" -ErrorAction SilentlyContinue
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
}

$registry = [ordered]@{
  version = 1
  generated_at = (Get-Date).ToString("s") + "Z"
  services = $services
}

$registry | ConvertTo-Json -Depth 4 | Out-File -FilePath $Output -Encoding UTF8
Write-Host "✅ Wrote mesh registry to $Output with $($services.Keys.Count) services" -ForegroundColor Green
