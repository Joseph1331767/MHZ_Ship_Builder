# adopt-into.ps1 - overlay this template's "repo layer" (agentic setup) onto another Godot project.
#
# Copies the agent config (.claude, .agents, AGENTS/CLAUDE/GEMINI.md, .mcp.json, hooks, skills,
# bootstrap) into a TARGET repo WITHOUT touching its game code, project.godot, scenes, or addons.
# Existing files are skipped (report only) unless -Force. .gitignore/.gitattributes are merge-appended.
#
# Usage from the target repo root:
#   powershell -ExecutionPolicy Bypass -File <template>\scripts\adopt-into.ps1
# Or explicitly:
#   ... adopt-into.ps1 -Source D:\soft\claude_adventures -Target D:\games\my-existing-game
#
# ASCII-only for Windows PowerShell 5.1 safety.

param(
    [string]$Source,
    [string]$Target = (Get-Location).Path,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$TEMPLATE_REPO = 'Joseph1331767/godot-agent-template'
$DEFAULT_LOCAL = 'D:\soft\claude_adventures'

function Write-Step($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[copy] $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "[skip] $msg (already exists - not overwritten)" -ForegroundColor DarkGray }
function Write-Merge($msg){ Write-Host "[merge] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }

# --- 1. Resolve the template source ----------------------------------------
function Resolve-Source {
    if ($Source -and (Test-Path (Join-Path $Source 'AGENTS.md'))) { return (Resolve-Path $Source).Path }
    if ($env:GODOT_TEMPLATE -and (Test-Path (Join-Path $env:GODOT_TEMPLATE 'AGENTS.md'))) { return $env:GODOT_TEMPLATE }
    if (Test-Path (Join-Path $DEFAULT_LOCAL 'AGENTS.md')) { return $DEFAULT_LOCAL }
    Write-Step "No local template found - cloning $TEMPLATE_REPO from GitHub..."
    $tmp = Join-Path $env:TEMP ("godot-template-" + [System.Guid]::NewGuid().ToString('N').Substring(0,8))
    gh repo clone $TEMPLATE_REPO $tmp -- --depth 1 | Out-Null
    if (-not (Test-Path (Join-Path $tmp 'AGENTS.md'))) { throw "Could not obtain the template (checked -Source, GODOT_TEMPLATE, $DEFAULT_LOCAL, and gh clone)." }
    return $tmp
}

$src = Resolve-Source
$dst = (Resolve-Path $Target).Path
Write-Host ""
Write-Step "=== Adopting Godot agentic setup ==="
Write-Host "  Source: $src"
Write-Host "  Target: $dst"
if ($src -eq $dst) { throw "Source and target are the same directory - nothing to do." }
Write-Host ""

# --- 2. Copy helpers --------------------------------------------------------
function Copy-Item-Safe($rel) {
    $from = Join-Path $src $rel
    $to   = Join-Path $dst $rel
    if (-not (Test-Path $from)) { return }
    if ((Test-Path $to) -and -not $Force) { Write-Skip $rel; return }
    $parent = Split-Path $to -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force $parent | Out-Null }
    Copy-Item $from $to -Recurse -Force
    Write-Ok $rel
}

function Merge-Lines($rel) {
    $from = Join-Path $src $rel
    $to   = Join-Path $dst $rel
    if (-not (Test-Path $from)) { return }
    if (-not (Test-Path $to)) { Copy-Item $from $to -Force; Write-Ok $rel; return }
    $have = Get-Content $to
    $want = Get-Content $from
    $add  = $want | Where-Object { $_ -and ($have -notcontains $_) }
    if ($add) {
        Add-Content $to "`n# --- appended by adopt-into.ps1 ---"
        $add | ForEach-Object { Add-Content $to $_ }
        Write-Merge "$rel (+$($add.Count) line(s))"
    } else { Write-Skip "$rel (nothing new to merge)" }
}

# --- 3. Overlay the repo layer ---------------------------------------------
Write-Step "Agent config:"
Copy-Item-Safe '.claude/hooks'
Copy-Item-Safe '.claude/skills'
Copy-Item-Safe '.claude/agents'
Copy-Item-Safe '.claude/settings.json'
Copy-Item-Safe '.agents'
Copy-Item-Safe '.mcp.json'

Write-Step "Rules docs:"
Copy-Item-Safe 'AGENTS.md'
Copy-Item-Safe 'CLAUDE.md'
Copy-Item-Safe 'GEMINI.md'

Write-Step "Scripts:"
Copy-Item-Safe 'scripts/bootstrap.ps1'
Copy-Item-Safe 'scripts/setup-machine.ps1'
Copy-Item-Safe 'scripts/adopt-into.ps1'

Write-Step "Docs skeleton:"
Copy-Item-Safe 'docs/adr/template.md'
if (-not (Test-Path (Join-Path $dst 'docs/devlog/CHANGELOG.md'))) {
    New-Item -ItemType Directory -Force (Join-Path $dst 'docs/devlog') | Out-Null
    Set-Content (Join-Path $dst 'docs/devlog/CHANGELOG.md') "# Dev Log`n`nAppend-only, chronological. Newest entries at the END.`n" -Encoding utf8
    Write-Ok 'docs/devlog/CHANGELOG.md (new)'
} else { Write-Skip 'docs/devlog/CHANGELOG.md' }

Write-Step "Git hygiene:"
Merge-Lines '.gitignore'
Merge-Lines '.gitattributes'

# --- 4. project.godot: never overwritten - report what to add ---------------
Write-Host ""
$targetGodot = Join-Path $dst 'project.godot'
if (Test-Path $targetGodot) {
    $pg = Get-Content $targetGodot -Raw
    if ($pg -notmatch 'untyped_declaration=2') {
        Write-Warn "project.godot exists but lacks the strict-typing warnings. Add this block (via Godot editor or by hand):"
        Write-Host @'

[debug]

gdscript/warnings/untyped_declaration=2
gdscript/warnings/inferred_declaration=1
gdscript/warnings/unsafe_property_access=1
gdscript/warnings/unsafe_method_access=1
gdscript/warnings/unsafe_cast=1
gdscript/warnings/unsafe_call_argument=1
gdscript/warnings/untyped_signal=1
'@ -ForegroundColor Gray
    } else { Write-Ok 'project.godot already has strict-typing warnings' }
} else {
    Write-Warn "No project.godot in target - is this a Godot project? (a fresh project should start from NEW_PROJECT.md instead)"
}

# --- 5. Manual next steps ---------------------------------------------------
Write-Host ""
Write-Step "=== Done. Manual next steps ==="
Write-Host "1. Run this project's bootstrap to fetch addons + verify the machine layer:"
Write-Host "     powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1"
Write-Host "2. Open the project in Godot 4.7 -> Project Settings -> Plugins: enable 'gdUnit4' and 'Godot AI'."
Write-Host "3. In Claude Code: /mcp -> approve godot-ai + context7. In Antigravity: reopen the folder."
Write-Host "4. If AGENTS.md/CLAUDE.md were [skip]ped, this repo already had its own - merge by hand if needed."
Write-Host "5. Fill in AGENTS.md section 1 (project name/vision) and create docs/PROJECT_NODE_OF_TRUTH.md."
