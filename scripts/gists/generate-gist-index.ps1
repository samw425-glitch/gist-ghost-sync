param(
  [string]$ReposFile = "repos.txt",
  [string]$Output = "gist.md"
)

$ErrorActionPreference = "Stop"

# Ensure gh CLI is available
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI 'gh' is required. Install from https://cli.github.com/ and authenticate: gh auth login"
}

if (-not (Test-Path $ReposFile)) {
  throw "Repos file not found: $ReposFile"
}

$repos = Get-Content $ReposFile | Where-Object { $_ -and -not $_.Trim().StartsWith('#') } | ForEach-Object { $_.Trim() }
if (-not $repos -or $repos.Count -eq 0) {
  throw "No repositories found in $ReposFile"
}

$lines = @()
$lines += "# Repository Index"
$lines += ""

foreach ($r in $repos) {
  try {
    $json = gh repo view $r --json nameWithOwner,url,description,primaryLanguage,stargazerCount,updatedAt --jq '.'
    $info = $json | ConvertFrom-Json
    $name = $info.nameWithOwner
    $url = $info.url
    $desc = if ($info.description) { $info.description } else { '' }
    $lang = if ($info.primaryLanguage) { $info.primaryLanguage.name } else { 'n/a' }
    $stars = if ($info.stargazerCount -ne $null) { $info.stargazerCount } else { 0 }
    $updated = Get-Date $info.updatedAt -Format 'yyyy-MM-dd'

    $lines += "- [$name]($url) - $desc (lang: $lang, stars: $stars, updated: $updated)"
  } catch {
    Write-Host "Failed to query $r : $($_.Exception.Message)" -ForegroundColor Yellow
    $lines += "- $r - (metadata unavailable)"
  }
}

$lines -join "`n" | Out-File -FilePath $Output -Encoding UTF8
Write-Host "Wrote $Output" -ForegroundColor Green
