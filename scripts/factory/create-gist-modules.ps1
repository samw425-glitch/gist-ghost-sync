param(
  [Parameter(Mandatory=$true)]
  [string]$ReposFile,
  [Parameter(Mandatory=$false)]
  [string]$OutputFile = "out/modules.json"
)

function Get-DefaultBranch($ownerRepo) {
  $info = gh api "repos/$ownerRepo" | ConvertFrom-Json
  return $info.default_branch
}

function Get-FilesForModule($ownerRepo, $branch, $patterns) {
  $branchInfo = gh api "repos/$ownerRepo/branches/$branch" | ConvertFrom-Json
  $commitSha = $branchInfo.commit.sha
  $commitInfo = gh api "repos/$ownerRepo/git/commits/$commitSha" | ConvertFrom-Json
  $treeSha = $commitInfo.tree.sha
  $tree = gh api "repos/$ownerRepo/git/trees/$treeSha?recursive=1" | ConvertFrom-Json
  $files = @()
  foreach ($n in $tree.tree) {
    if ($n.type -ne 'blob') { continue }
    $p = [string]$n.path
    $match = $false
    foreach ($inc in $patterns) {
      $like = $inc -replace '\*\*','*'
      if ($p -like $like) { $match = $true; break }
    }
    if ($match) { $files += $p }
  }
  return $files
}

$repos = Get-Content -Path $ReposFile | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
$results = @()

foreach ($ownerRepo in $repos) {
  Write-Host "🧩 Modules for $ownerRepo" -ForegroundColor Cyan
  $branch = Get-DefaultBranch $ownerRepo
  # Load manifest
  $manifest = $null
  try {
    $manApi = "repos/$ownerRepo/contents/.factory/publish.manifest.json?ref=$branch"
    $raw = gh api $manApi 2>$null
    if ($LASTEXITCODE -eq 0 -and $raw) {
      $o = $raw | ConvertFrom-Json
      if ($o.content) {
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($o.content -replace "\n","")))
        $manifest = $decoded | ConvertFrom-Json
      }
    }
  } catch { }
  if (-not $manifest -or -not $manifest.modules) { continue }

  foreach ($mod in $manifest.modules) {
    $name = [string]$mod.name
    $patterns = @() + $mod.files
    $files = Get-FilesForModule $ownerRepo $branch $patterns
    if ($files.Count -eq 0) { continue }

    # Download files locally
    $tmpDir = Join-Path $env:RUNNER_TEMP ([System.Guid]::NewGuid().ToString())
    if (-not $tmpDir) { $tmpDir = Join-Path $pwd ("tmp_" + [System.Guid]::NewGuid().ToString()) }
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $paths = @()
    foreach ($f in $files) {
      $api = "repos/$ownerRepo/contents/$f?ref=$branch"
      $dest = Join-Path $tmpDir ([System.IO.Path]::GetFileName($f))
      gh api -H "Accept: application/vnd.github.raw" $api --output "$dest" 2>$null | Out-Null
      if (Test-Path $dest) { $paths += $dest }
    }
    if ($paths.Count -eq 0) { continue }

    $desc = if ($mod.description) { [string]$mod.description } else { "$ownerRepo module: $name" }
    $visibility = if ($mod.visibility) { [string]$mod.visibility } else { "secret" }
    $isPublic = $visibility -eq "public"

    # Create gist
    $cmd = "gh gist create `"$($paths -join '`" `"')`" -d `"$desc`" -f"
    if ($isPublic) { $cmd += " -p" }
    $url = Invoke-Expression $cmd
    $id = (Select-String -InputObject $url -Pattern "https://gist.github.com/[^/]+/([a-f0-9]+)" -AllMatches).Matches[0].Groups[1].Value
    $meta = gh api "gists/$id" | ConvertFrom-Json
    $filesOut = @()
    foreach ($k in $meta.files.PSObject.Properties.Name) {
      $filesOut += [ordered]@{ filename=$k; raw_url=$meta.files[$k].raw_url }
    }

    $results += [ordered]@{
      ownerRepo  = $ownerRepo
      branch     = $branch
      module     = $name
      gist_id    = $id
      gist_url   = $url
      visibility = $visibility
      description= $desc
      files      = $filesOut
    }
  }
}

New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($OutputFile)) -Force | Out-Null
($results | ConvertTo-Json -Depth 6) | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "✅ Wrote modules index: $OutputFile (count=$($results.Count))" -ForegroundColor Green
