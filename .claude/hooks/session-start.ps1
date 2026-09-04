# SessionStart: inject recent dev log + git state into the new session's context.
# Stdout from this hook becomes context. Always exits 0.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$proj = $env:CLAUDE_PROJECT_DIR
if (-not $proj) { $proj = (Get-Location).Path }

$log = Join-Path $proj 'docs\devlog\CHANGELOG.md'
if (Test-Path $log) {
    Write-Output '## Recent dev log (tail of docs/devlog/CHANGELOG.md)'
    Get-Content $log -Tail 25
    Write-Output ''
}

Write-Output '## Git state'
git -C $proj status -sb 2>$null
git -C $proj log --oneline -5 2>$null
exit 0
