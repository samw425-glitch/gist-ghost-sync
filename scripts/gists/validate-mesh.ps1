param(
  [Parameter(Mandatory=$false)]
  [string]$EnvName = "dev",
  [Parameter(Mandatory=$false)]
  [string]$GistId,
  [Parameter(Mandatory=$false)]
  [string]$RawUrl,
  [switch]$Strict
)

if (-not $RawUrl) {
  if (-not $GistId) { throw "Provide -GistId or -RawUrl" }
  $gistJson = gh api "gists/$GistId" | ConvertFrom-Json
  $file = $gistJson.files["mesh.json"]
  if (-not $file -or -not $file.raw_url) { throw "mesh.json not found in gist $GistId" }
  $RawUrl = $file.raw_url
}

Write-Host "🔎 Validating mesh for [$EnvName] from: $RawUrl" -ForegroundColor Cyan
$ok = $true
$summary = @()
try {
  $mesh = Invoke-RestMethod -Uri $RawUrl -TimeoutSec 15
} catch {
  Write-Host "Failed to fetch mesh: $($_.Exception.Message)" -ForegroundColor Red
  if ($Strict) { exit 1 } else { exit 0 }
}

$services = $mesh.services.GetEnumerator() | ForEach-Object { $_ }
foreach ($svc in $services) {
  $name = $svc.Key
  $url = $svc.Value.url
  $health = $svc.Value.health
  $target = "$url$health"
  try {
    $resp = Invoke-WebRequest -Uri $target -TimeoutSec 5 -Method GET -ErrorAction Stop
    $status = $resp.StatusCode
    $okRow = ($status -ge 200 -and $status -lt 400)
    if (-not $okRow) { $ok = $false }
    $summary += "| $name | $target | $status |"
  } catch {
    $ok = $false
    $summary += "| $name | $target | ERROR |"
  }
}

$report = @()
$report += "# Mesh Validation Report ($EnvName)"
$report += "| Service | URL | Status |"
$report += "|---------|-----|--------|"
$report += $summary
$reportText = ($report -join "`n")
Set-Content -Path "mesh-validation-$EnvName.md" -Value $reportText -Encoding UTF8

if ($Strict -and -not $ok) { exit 1 } else { exit 0 }
