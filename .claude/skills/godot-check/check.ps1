# Headless Godot parse check with hard timeout (Windows-safe).
# Usage: check.ps1            -> whole-project import/parse check
#        check.ps1 -File x.gd -> --check-only a single script
param([string]$File)

$ErrorActionPreference = 'Continue'

if (-not $env:GODOT_BIN -or -not (Test-Path $env:GODOT_BIN)) {
    Write-Error "GODOT_BIN is not set or does not exist. Set it to the Godot console exe."
    exit 1
}

$proj = $env:CLAUDE_PROJECT_DIR
if (-not $proj) { $proj = (Get-Location).Path }

if ($File) {
    $godotArgs = @('--headless', '--path', $proj, '--check-only', '-s', $File)
} else {
    $godotArgs = @('--headless', '--path', $proj, '--import')
}

$outFile = Join-Path $env:TEMP 'godot_check_out.txt'
$errFile = Join-Path $env:TEMP 'godot_check_err.txt'

$p = Start-Process -FilePath $env:GODOT_BIN -ArgumentList $godotArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile

if (-not $p.WaitForExit(90000)) {
    $p.Kill()
    Start-Sleep -Milliseconds 300
    Write-Output "TIMEOUT: Godot did not exit within 90s and was killed. Output so far:"
    Get-Content $outFile, $errFile -ErrorAction SilentlyContinue
    exit 124
}

Get-Content $outFile, $errFile -ErrorAction SilentlyContinue
exit $p.ExitCode
