# setup-machine.ps1
# Installs EVERY command-line prerequisite for the dual-agent Godot workflow on a fresh
# Windows 10/11 machine, then sets GODOT_BIN and PATH. Safe to re-run (idempotent).
#
# Run from anywhere:   powershell -ExecutionPolicy Bypass -File scripts\setup-machine.ps1
#
# NOTE: the two AI apps themselves (Claude Code CLI, Google Antigravity) are NOT winget
#       packages - this script detects them and tells you where to get them. See FRESH_MACHINE.md.

$ErrorActionPreference = 'Continue'

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Winget-Ensure($id, $probe, $label) {
    if ($probe -and (Have $probe)) {
        Write-Host "[OK]   $label already installed" -ForegroundColor Green
        return
    }
    Write-Host "Installing $label ($id) ..." -ForegroundColor Cyan
    winget install --id $id --accept-source-agreements --accept-package-agreements --silent
    if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] winget returned $LASTEXITCODE for $label (may already be installed)" -ForegroundColor Yellow }
}

Write-Host "=== Fresh-machine setup for the dual-agent Godot workflow ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Core CLI tools via winget ------------------------------------------
Winget-Ensure 'Git.Git'                  'git'     'Git'
Winget-Ensure 'GitHub.GitLFS'            'git-lfs' 'Git LFS'
Winget-Ensure 'GitHub.cli'              'gh'      'GitHub CLI'
Winget-Ensure 'OpenJS.NodeJS'            'node'    'Node.js'
Winget-Ensure 'Python.Python.3.12'       'python'  'Python 3.12'
Winget-Ensure 'astral-sh.uv'             'uv'      'uv (runs the godot-ai MCP server)'
Winget-Ensure 'GodotEngine.GodotEngine'  $null     'Godot 4.x'

# --- 2. git-lfs global hook -------------------------------------------------
if (Have 'git-lfs') { git lfs install *> $null; Write-Host "[OK]   git lfs installed (global hooks)" -ForegroundColor Green }

# --- 3. GODOT_BIN (discover the console exe winget just placed) -------------
$godot = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter 'Godot_v*_console.exe' -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
if ($godot) {
    [Environment]::SetEnvironmentVariable('GODOT_BIN', $godot, 'User')
    $env:GODOT_BIN = $godot
    Write-Host "[OK]   GODOT_BIN -> $godot" -ForegroundColor Green
} else {
    Write-Host "[WARN] Could not find the Godot console exe. If Godot installed elsewhere, set GODOT_BIN by hand:" -ForegroundColor Yellow
    Write-Host '       [Environment]::SetEnvironmentVariable("GODOT_BIN","<path to Godot_v...console.exe>","User")' -ForegroundColor Yellow
}

# --- 4. gdtoolkit (gdlint / gdformat) via pip -------------------------------
$pip = $null
foreach ($cand in @('pip', 'python', 'py')) { if (Have $cand) { $pip = $cand; break } }
if ($pip) {
    Write-Host "Installing gdtoolkit (gdlint/gdformat) ..." -ForegroundColor Cyan
    switch ($pip) {
        'pip'    { pip install "gdtoolkit==4.*" }
        default  { & $pip -m pip install "gdtoolkit==4.*" }
    }
} else {
    Write-Host "[WARN] Python/pip not on PATH yet (just installed). Open a NEW shell and re-run this script to finish gdtoolkit." -ForegroundColor Yellow
}

# --- 5. Add ~/.local/bin to PATH (Claude Code's native install location) ----
$localBin = "$env:USERPROFILE\.local\bin"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ((Test-Path $localBin) -and ($userPath -notlike "*$localBin*")) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$localBin", 'User')
    Write-Host "[OK]   added $localBin to PATH" -ForegroundColor Green
}

# --- 6. Detect the two AI apps (manual installs) ----------------------------
Write-Host ""
Write-Host "=== AI apps (install these yourself - not winget packages) ===" -ForegroundColor Cyan
if ((Have 'claude') -or (Test-Path "$localBin\claude.exe")) { Write-Host "[OK]   Claude Code CLI found" -ForegroundColor Green }
else { Write-Host "[TODO] Claude Code CLI  -> install per https://code.claude.com/docs (native installer, or 'npm install -g @anthropic-ai/claude-code')" -ForegroundColor Yellow }

if (Test-Path "$env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe") { Write-Host "[OK]   Antigravity found" -ForegroundColor Green }
else { Write-Host "[TODO] Google Antigravity -> download from https://antigravity.google" -ForegroundColor Yellow }

# --- 6b. Machine-global agent config (Claude skills + Antigravity rules/MCP) --
Write-Host ""
$installGlobal = Join-Path $PSScriptRoot 'install-global-config.ps1'
if (Test-Path $installGlobal) {
    Write-Host "Installing machine-global agent config (global skills + Antigravity rules)..." -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installGlobal
} else {
    Write-Host "[WARN] install-global-config.ps1 not found - global Claude skills not installed." -ForegroundColor Yellow
}

# --- 7. Done ----------------------------------------------------------------
Write-Host ""
Write-Host "=== Next ===" -ForegroundColor Cyan
Write-Host "1. CLOSE this shell and open a NEW one so all the new commands + GODOT_BIN are picked up."
Write-Host "2. (optional) re-run this script in the new shell if it reported any [WARN]/[TODO] above."
Write-Host "3. In the project folder: powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1"
Write-Host "4. Then follow docs\FIRST_RUN.md (enable Godot plugins, approve MCP, etc.)."
