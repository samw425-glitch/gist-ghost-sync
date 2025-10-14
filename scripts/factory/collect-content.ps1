param(
  [Parameter(Mandatory=$true)]
  [string]$ReposFile,
  [Parameter(Mandatory=$false)]
  [string]$OutputDir = "out",
  [Parameter(Mandatory=$false)]
  [int]$MaxSizeMB = 25
)

function Get-DefaultBranch($ownerRepo) {
  $info = gh api "repos/$ownerRepo" | ConvertFrom-Json
  return $info.default_branch
}

function Get-Tree($ownerRepo, $branch) {
  $branchInfo = gh api "repos/$ownerRepo/branches/$branch" | ConvertFrom-Json
  $commitSha = $branchInfo.commit.sha
  $commitInfo = gh api "repos/$ownerRepo/git/commits/$commitSha" | ConvertFrom-Json
  $treeSha = $commitInfo.tree.sha
  $tree = gh api "repos/$ownerRepo/git/trees/$treeSha?recursive=1" | ConvertFrom-Json
  return $tree.tree
}

function Match-Include($path, $manifest) {
  # If manifest present, use its include/extensions logic
  if ($manifest) {
    $includes = @()
    if ($manifest.defaults -and $manifest.defaults.include) { $includes += $manifest.defaults.include }
    if ($manifest.include) { $includes += $manifest.include }
    if ($includes.Count -gt 0) {
      foreach ($inc in $includes) {
        $p = [string]$inc
        $p = $p -replace '\.','\.'
        $p = $p -replace '\*\*','*'
        $p = $p -replace '\*','.*'
        if ($path -match "^$p$") { return $true }
        if ($path -like $inc) { return $true }
      }
    }
    $exts = @('*.png','*.jpg','*.jpeg','*.gif','*.svg','*.webp','*.mp4','*.webm','*.pdf','*.md','*.txt','*.json','*.csv')
    if ($manifest.defaults -and $manifest.defaults.extensions) { $exts = @() + $manifest.defaults.extensions | ForEach-Object { "*.$_" } }
    foreach ($e in $exts) { if ($path -like $e) { return $true } }
    return $false
  }
  # Default heuristics
  $exts = @('*.png','*.jpg','*.jpeg','*.gif','*.svg','*.webp','*.mp4','*.webm','*.pdf','*.md','*.txt','*.json','*.csv')
  foreach ($e in $exts) { if ($path -like $e) { return $true } }
  if ($path -like 'public/*' -or $path -like 'public/*/*' -or $path -like 'docs/*' -or $path -like 'assets/*' -or $path -like 'static/*') { return $true }
  return $false
}

$repos = Get-Content -Path $ReposFile | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
$maxBytes = $MaxSizeMB * 1MB

$catalog = @()

foreach ($ownerRepo in $repos) {
  Write-Host "📦 Scanning $ownerRepo" -ForegroundColor Cyan
  try {
    $branch = Get-DefaultBranch $ownerRepo
  } catch {
    Write-Host "  ! Failed to get default branch for $ownerRepo: $($_.Exception.Message)" -ForegroundColor Yellow
    continue
  }
  try {
    $tree = Get-Tree $ownerRepo $branch
  } catch {
    Write-Host "  ! Failed to get tree for $ownerRepo@$branch: $($_.Exception.Message)" -ForegroundColor Yellow
    continue
  }

  # Load optional publish manifest
  $manifest = $null
  try {
    $manApi = "repos/$ownerRepo/contents/.factory/publish.manifest.json?ref=$branch"
    $raw = gh api $manApi 2>$null
    if ($LASTEXITCODE -eq 0 -and $raw) {
      $o = $raw | ConvertFrom-Json
      if ($o.content) {
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($o.content -replace "\n","")))
        $manifest = $decoded | ConvertFrom-Json
        Write-Host "  • Using publish.manifest.json for $ownerRepo" -ForegroundColor Green
        if ($manifest.defaults -and $manifest.defaults.maxSizeMB) {
          $maxBytes = [int]$manifest.defaults.maxSizeMB * 1MB
        }
      }
    }
  } catch { }

  foreach ($node in $tree) {
    if ($node.type -ne 'blob') { continue }
    $path = [string]$node.path
    if (-not (Match-Include $path, $manifest)) { continue }
    if ($node.size -and [int64]$node.size -gt $maxBytes) { continue }

    $safeRepo = $ownerRepo -replace '/','__'
    $dest = Join-Path $OutputDir (Join-Path $safeRepo $path)
    New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($dest)) -Force | Out-Null

    $api = "repos/$ownerRepo/contents/$path?ref=$branch"
    $ok = $true
    try {
      gh api -H "Accept: application/vnd.github.raw" $api --output "$dest" | Out-Null
    } catch {
      Write-Host "  ! Failed to download $ownerRepo/$path: $($_.Exception.Message)" -ForegroundColor Yellow
      $ok = $false
    }
    if (-not $ok) { continue }

    $item = [ordered]@{
      ownerRepo = $ownerRepo
      branch    = $branch
      path      = $path
      rel_path  = "$safeRepo/$path"
      size      = (Get-Item "$dest").Length
      url       = "https://raw.githubusercontent.com/$ownerRepo/$branch/$path"
      sha       = $node.sha
      content_type = ""
    }
    # Apply global metadata from manifest
    if ($manifest -and $manifest.metadata) { $item.metadata = $manifest.metadata }
    $catalog += $item
  }
}

$newCatalogPath = Join-Path $OutputDir "files.json"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
($catalog | ConvertTo-Json -Depth 6) | Out-File -FilePath $newCatalogPath -Encoding UTF8
Write-Host "✅ Wrote catalog: $newCatalogPath (items=$($catalog.Count))" -ForegroundColor Green
