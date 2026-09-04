# PostToolUse (Edit|Write): auto-format edited GDScript with gdformat.
# Always exits 0 — formatting is best-effort, never blocking.
$ErrorActionPreference = 'SilentlyContinue'

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $hook = $raw | ConvertFrom-Json } catch { exit 0 }

$path = $hook.tool_input.file_path
if ($path -and ($path -match '\.gd$') -and (Test-Path $path)) {
    if (Get-Command gdformat -ErrorAction SilentlyContinue) {
        & gdformat $path *> $null
    }
}
exit 0
