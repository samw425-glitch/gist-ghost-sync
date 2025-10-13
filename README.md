# Gist Ghost Sync

Aggregates summaries of multiple GitHub repositories into a single Gist.

How it works
- You list repos in repos.txt (format: owner/repo per line)
- A PowerShell script queries GitHub for metadata and builds a markdown index (gist.md)
- A GitHub Actions workflow publishes/updates a Gist using the GitHub CLI

Quick start
- Edit repos.txt and add lines like:
  - samw425-glitch/hydra
  - samw425-glitch/grandslam-stack
- Run locally (requires gh CLI authenticated):
```powershell path=null start=null
pwsh -File scripts/gists/generate-gist-index.ps1 -ReposFile .\repos.txt -Output gist.md
```
- In GitHub CI, add secrets:
  - GH_TOKEN_GIST: a token with the gist scope
  - GIST_ID (optional): to update an existing gist; omit to create a new one

Files
- scripts/gists/generate-gist-index.ps1 — builds gist.md from repos.txt using gh CLI
- repos.txt — list of repos to include (owner/repo per line)
- .github/workflows/gist-ghost-sync.yml — publishes gist.md to your Gist on push or manual trigger

Notes
- The script uses gh repo view to fetch repo metadata. Make sure gh is installed locally or available in CI.
- No secrets are stored in this repo. Configure secrets in the GitHub repository settings when you push it online.