# bootstrap.ps1 — one-shot setup check + addon fetch for a project created from this template.
# Run from the repo root:  powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

Write-Host "=== Agent Base Template bootstrap ===" -ForegroundColor Cyan

# --- 1. Environment checks -------------------------------------------------
$ok = $true
function Check($name, $test, $fix) {
    if ($test) { Write-Host "[OK]   $name" -ForegroundColor Green }
    else       { Write-Host "[MISS] $name -> $fix" -ForegroundColor Yellow; $script:ok = $false }
}

Check "GODOT_BIN env var"  ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) "set user env var GODOT_BIN to the Godot 4.x console exe"
Check "git"                (Get-Command git    -ErrorAction SilentlyContinue) "winget install Git.Git"
Check "git-lfs"            (Get-Command git-lfs -ErrorAction SilentlyContinue) "winget install GitHub.GitLFS"
Check "uv (godot-ai MCP)"  (Get-Command uv     -ErrorAction SilentlyContinue) "winget install astral-sh.uv"
Check "gdlint (gdtoolkit)" (Get-Command gdlint -ErrorAction SilentlyContinue) "pip install `"gdtoolkit==4.*`""

# --- 2. Fetch addons (best-effort) ------------------------------------------
function Install-AddonFromZip($name, $zipUrl) {
    $dest = Join-Path $root 'addons'
    if (Test-Path (Join-Path $dest $name)) {
        Write-Host "[OK]   addon '$name' already present" -ForegroundColor Green
        return
    }
    try {
        Write-Host "Downloading $name ..." -ForegroundColor Cyan
        $tmp = Join-Path $env:TEMP "bootstrap_$name"
        $zip = "$tmp.zip"
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        # find any addons/<dir> inside the extracted tree and copy it in
        $found = Get-ChildItem $tmp -Recurse -Directory | Where-Object { $_.Parent.Name -eq 'addons' }
        if (-not $found) { throw "no addons/ directory inside the zip" }
        New-Item -ItemType Directory -Force $dest | Out-Null
        foreach ($d in $found) {
            Copy-Item $d.FullName -Destination $dest -Recurse -Force
            Write-Host "[OK]   installed addons\$($d.Name)" -ForegroundColor Green
        }
        Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[FAIL] $name download failed ($($_.Exception.Message))." -ForegroundColor Yellow
        Write-Host "       Install manually in Godot: AssetLib tab -> search '$name' -> Download -> Install." -ForegroundColor Yellow
    }
}

Install-AddonFromZip 'gdUnit4' 'https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/heads/master.zip'
Install-AddonFromZip 'godot-ai' 'https://github.com/hi-godot/godot-ai/archive/refs/heads/main.zip'

# --- 3. Next steps -----------------------------------------------------------
Write-Host ""
Write-Host "=== Manual next steps ===" -ForegroundColor Cyan
Write-Host "1. Open the project in Godot 4.7 -> Project -> Project Settings -> Plugins:"
Write-Host "   enable 'gdUnit4' and 'Godot AI' (the AI dock starts the MCP server on port 8000)."
Write-Host "2. In the Godot AI dock, click Auto-configure to register the MCP server with"
Write-Host "   Claude Code / Antigravity, or rely on the committed .mcp.json / .agents/mcp_config.json."
Write-Host "3. Rename the project: project.godot (config/name) + AGENTS.md section 1."
Write-Host "4. See NEW_PROJECT.md for the full checklist."
if (-not $ok) { Write-Host "NOTE: fix the [MISS] items above first." -ForegroundColor Yellow }
