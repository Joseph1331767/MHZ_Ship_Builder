# Stop hook: lint changed .gd files with gdlint (pure Python — no Godot process, no hang risk).
# Exit 2 blocks the stop and feeds errors back so the agent fixes them before finishing.
$ErrorActionPreference = 'SilentlyContinue'

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $hook = $raw | ConvertFrom-Json } catch { exit 0 }

# Prevent infinite stop loops
if ($hook.stop_hook_active) { exit 0 }

$proj = $env:CLAUDE_PROJECT_DIR
if (-not $proj) { exit 0 }
if (-not (Get-Command gdlint -ErrorAction SilentlyContinue)) { exit 0 }

$changed = @(git -C $proj diff --name-only HEAD -- '*.gd' 2>$null) +
           @(git -C $proj ls-files --others --exclude-standard -- '*.gd' 2>$null) |
           Where-Object { $_ } | Select-Object -Unique
if (-not $changed) { exit 0 }

$failures = @()
$ErrorActionPreference = 'Continue'  # required so gdlint's stderr survives 2>&1 in PS 5.1
foreach ($f in $changed) {
    $full = Join-Path $proj $f
    if (Test-Path $full) {
        $out = (& gdlint $full 2>&1 | ForEach-Object { $_.ToString() } | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { $failures += "--- $f ---"; $failures += $out }
    }
}
$ErrorActionPreference = 'SilentlyContinue'

if ($failures.Count -gt 0) {
    [Console]::Error.WriteLine("gdlint found problems in changed GDScript files. Fix them before finishing:`n" + ($failures -join "`n"))
    exit 2
}
exit 0
