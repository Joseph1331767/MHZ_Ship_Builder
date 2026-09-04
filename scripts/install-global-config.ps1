# install-global-config.ps1 - replicate the MACHINE-GLOBAL agent config on this PC.
#
# The repo layer (AGENTS.md, .claude/, etc.) travels inside each project. But two pieces live OUTSIDE any
# repo, in your home dir, and would be lost on a fresh machine:
#   - Claude Code global skills:  ~/.claude/skills/  (new-godot-project, adopt-godot-setup)
#   - Antigravity global config:  ~/.gemini/GEMINI.md rules + ~/.gemini/config/mcp_config.json
# This script installs the vendored source-of-truth copies from machine/ into those locations.
#
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File scripts\install-global-config.ps1
# Safe to re-run (idempotent). ASCII-only for Windows PowerShell 5.1 safety.

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$machine = Join-Path $repo 'machine'

function Write-Ok($m)   { Write-Host "[ok]   $m" -ForegroundColor Green }
function Write-Skip($m) { Write-Host "[skip] $m" -ForegroundColor DarkGray }
function Write-Warn($m) { Write-Host "[warn] $m" -ForegroundColor Yellow }

Write-Host "=== Installing machine-global agent config ===" -ForegroundColor Cyan

# --- 1. Claude Code global skills -> ~/.claude/skills/ ----------------------
$claudeSkills = Join-Path $env:USERPROFILE '.claude\skills'
New-Item -ItemType Directory -Force $claudeSkills | Out-Null
$srcSkills = Get-ChildItem (Join-Path $machine 'claude\skills') -Directory -ErrorAction SilentlyContinue
foreach ($s in $srcSkills) {
    Copy-Item $s.FullName -Destination $claudeSkills -Recurse -Force
    Write-Ok "claude skill '$($s.Name)' -> ~/.claude/skills/"
}

# --- 2. Antigravity global rules -> ~/.gemini/GEMINI.md (append, idempotent) -
$geminiMd = Join-Path $env:USERPROFILE '.gemini\GEMINI.md'
$appendSrc = Join-Path $machine 'gemini\GEMINI.append.md'
$marker = 'BEGIN godot-agent-template'
if (Test-Path $appendSrc) {
    New-Item -ItemType Directory -Force (Split-Path $geminiMd -Parent) | Out-Null
    $current = if (Test-Path $geminiMd) { Get-Content $geminiMd -Raw } else { '' }
    if ($current -match $marker) {
        Write-Skip "~/.gemini/GEMINI.md already has the template block"
    } else {
        $block = Get-Content $appendSrc -Raw
        if ($current -and -not $current.EndsWith("`n")) { Add-Content $geminiMd "" }
        Add-Content $geminiMd "`n$block"
        Write-Ok "appended template block to ~/.gemini/GEMINI.md"
    }
}

# --- 3. Antigravity global MCP config -> ~/.gemini/config/mcp_config.json ----
$mcpDst = Join-Path $env:USERPROFILE '.gemini\config\mcp_config.json'
$mcpSrc = Join-Path $machine 'gemini\mcp_config.json'
if (Test-Path $mcpSrc) {
    if (Test-Path $mcpDst) {
        $same = (Get-Content $mcpDst -Raw) -eq (Get-Content $mcpSrc -Raw)
        if ($same) { Write-Skip "~/.gemini/config/mcp_config.json already matches" }
        else { Write-Warn "~/.gemini/config/mcp_config.json exists and DIFFERS - left as-is. Merge godot-ai + context7 by hand if missing." }
    } else {
        New-Item -ItemType Directory -Force (Split-Path $mcpDst -Parent) | Out-Null
        Copy-Item $mcpSrc $mcpDst -Force
        Write-Ok "installed ~/.gemini/config/mcp_config.json"
    }
}

Write-Host ""
Write-Host "Done. Restart Claude Code / Antigravity to pick up the new global skills + rules." -ForegroundColor Cyan
