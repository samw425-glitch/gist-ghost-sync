# Use official PowerShell image
FROM mcr.microsoft.com/powershell:latest

# Install GitHub CLI
RUN apt-get update && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install gh -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy application files
COPY . .

# Set permissions
RUN chmod +x scripts/gists/generate-gist-index.ps1

# Default command
CMD ["pwsh", "-File", "scripts/gists/generate-gist-index.ps1", "-ReposFile", "repos.txt", "-Output", "gist.md"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pwsh -Command "if (Test-Path 'gist.md') { exit 0 } else { exit 1 }"