#!/usr/bin/env node
/**
 * generate-gist-index.mjs
 * Cross-platform replacement for PowerShell script (Termux-friendly)
 */

import fs from "fs";
import path from "path";
import fetch from "node-fetch";

const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const OUTPUT_FILE = process.argv[2] || "gist-index.json";
const LOG_FILE = "generate-gist-index.log";

function log(level, message) {
  const timestamp = new Date().toISOString();
  const line = `${timestamp} [${level}] ${message}`;
  console.log(line);
  fs.appendFileSync(LOG_FILE, line + "\n");
}

async function main() {
  if (!GITHUB_TOKEN) {
    console.error("❌ ERROR: set GITHUB_TOKEN env var first!");
    process.exit(1);
  }

  log("INFO", "Starting Gist index generation.");

  const apiUrl = `https://api.github.com/gists?per_page=100`;

  const headers = {
    Authorization: `Bearer ${GITHUB_TOKEN}`,
    "User-Agent": "gist-sync-script",
    Accept: "application/vnd.github.v3+json",
  };

  const res = await fetch(apiUrl, { headers });

  if (!res.ok) {
    log("ERROR", `GitHub API responded with status ${res.status}`);
    process.exit(1);
  }

  const gists = await res.json();
  log("INFO", `Fetched ${gists.length} gists.`);

  const index = {
    generatedAt: new Date().toISOString(),
    gistCount: gists.length,
    items: gists.map((g) => ({
      id: g.id,
      description: g.description || "",
      url: g.html_url,
      createdAt: g.created_at,
      updatedAt: g.updated_at,
      public: g.public,
      fileCount: Object.keys(g.files || {}).length,
    })),
  };

  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(index, null, 2));
  log("INFO", `Index written to ${OUTPUT_FILE}`);
  log("INFO", "Done ✅");
  process.exit(0);
}

main().catch((err) => {
  log("ERROR", err.toString());
  process.exit(1);
});
