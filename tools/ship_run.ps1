<#
.SYNOPSIS
    Run a Godot tool script and FAIL on runtime script errors, not just on a bad exit code.

.DESCRIPTION
    A GDScript runtime error aborts the function it happened in, prints to stderr, and lets the
    frame carry on. That means a tool can print its own PASSED banner and exit 0 while one of its
    checks silently threw and never actually ran - the exit code says nothing about it. See
    AGENTS.md §8a, ported from the sibling MHZ_Materials project, which hit exactly this failure
    mode: a resolution-sheet page reported PASSED while throwing on every single draw.

    So every tool run goes through here. The exit code is the tool's own, unless the output
    contains a runtime error - then it is 1, and the offending lines are printed last so they are
    what a reader sees.

    The process is launched directly (not via a background job) specifically so a timeout can kill
    the real godot.exe by process id. AGENTS.md §8d already flags headless-under-run_in_background
    as a known Windows hang; a job-wrapper timeout here would risk the same failure mode one layer
    up, killing the job host while leaving godot.exe orphaned and still running.

.PARAMETER Script
    res:// path of the tool, e.g. res://tools/ship_selfcheck.gd

.PARAMETER Windowed
    Run with a window instead of --headless. Claim the GPU slot first (AGENTS.md §8c) - this
    module renders to a SubViewport and a windowed run competes for the same GPU as every other
    agent on the machine.

.PARAMETER Quiet
    Drop a tool's own verbose per-step trace lines (anything starting "[trace]" or "[map]") from
    the output shown on screen. The runtime-error scan still runs over the full, unfiltered output.

.PARAMETER TimeoutSeconds
    Kill the Godot process if it has not exited after this many seconds (default 120).

.PARAMETER ToolArgs
    Everything after the named parameters is forwarded to the tool script after a `--` separator,
    where OS.get_cmdline_user_args() picks it up.

    THIS PARAMETER EXISTS BECAUSE ITS ABSENCE BROKE THE GATE. tools/ship_shot.gd takes
    <scene> <out> <frames> <display_mode>, and with no way to pass them through the wrapper every
    screenshot was taken by invoking godot.exe directly - which skips the runtime-error scan below.
    Screenshots are the only check in this repo that looks at pixels, so they were the LAST thing
    that should have been running outside the gate.

.EXAMPLE
    ./tools/ship_run.ps1 res://tools/ship_selfcheck.gd
    ./tools/ship_run.ps1 res://tools/ship_validate_data.gd
    ./tools/ship_run.ps1 res://tools/ship_bake_cli.gd -Windowed -Quiet -TimeoutSeconds 300
#>
param(
    [Parameter(Mandatory = $true, Position = 0)] [string] $Script,
    [switch] $Windowed,
    [switch] $Quiet,
    [int] $TimeoutSeconds = 120,
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $ToolArgs = @()
)

$ErrorActionPreference = 'Continue'
if (-not $env:GODOT_BIN) { Write-Error 'GODOT_BIN is not set'; exit 2 }
if (-not (Test-Path $env:GODOT_BIN)) { Write-Error "GODOT_BIN does not point at a real file: $env:GODOT_BIN"; exit 2 }

$root = Split-Path -Parent $PSScriptRoot
$scriptArgs = @('--path', $root, '-s', $Script)
if (-not $Windowed) { $scriptArgs = @('--headless') + $scriptArgs }
# A leading '--' the caller typed themselves is redundant here; drop it so both spellings work.
$fwd = @($ToolArgs | Where-Object { $_ -ne '--' })
if ($fwd.Count -gt 0) { $scriptArgs += @('--') + $fwd }

# WHY NOT Start-Process -PassThru. It was used here first and it silently broke the gate.
# On this machine `$proc.ExitCode` comes back EMPTY after a redirected Start-Process run -- not 0,
# not 1, empty -- even after a parameterless WaitForExit() and with HasExited reporting True. The
# wrapper then did `exit $code`, PowerShell coerced $null to 0, and every tool reported success
# whatever it actually returned. `ship_validate_data.gd` printed "FAILED (18 errors)" and called
# quit(1), and this script exited 0. Verified directly: the same run under the call operator gives
# $LASTEXITCODE = 1, and under `cmd /c` gives 1, so Godot's exit code was always correct and only
# the wrapper was losing it.
#
# The call operator would fix the exit code but cannot kill an over-running Godot by PID, which is
# the orphaned-process hazard this wrapper exists to avoid. So drive System.Diagnostics.Process
# directly: it gives a reliable ExitCode, real redirection, and a killable handle.
#
# The streams are drained ASYNCHRONOUSLY and awaited only after WaitForExit. A synchronous
# ReadToEnd() before the wait deadlocks the moment Godot writes more than one pipe buffer.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $env:GODOT_BIN
# NOT ArgumentList: that property is .NET Core 2.1+, and Windows PowerShell 5.1 runs on .NET
# Framework, where it is null -- every Add() then throws InvokeMethodOnNull, the process never
# starts, and the run dies as a spurious TIMEOUT. Build a quoted string instead. Quote every
# argument so a path containing a space (Program Files, OneDrive, a user name with a space)
# cannot split into two arguments.
$psi.Arguments = ($scriptArgs | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = -not $Windowed

$proc = [System.Diagnostics.Process]::Start($psi)
$outTask = $proc.StandardOutput.ReadToEndAsync()
$errTask = $proc.StandardError.ReadToEndAsync()

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
    Write-Output ("TIMEOUT: {0} did not finish within {1}s - this run does NOT pass." -f $Script, $TimeoutSeconds)
    exit 1
}

$code = $proc.ExitCode
$lines = @()
$lines += ($outTask.Result -split "`r?`n")
$lines += ($errTask.Result -split "`r?`n")

# What counts as a thrown error. Deliberately narrow: these are the shapes GDScript actually
# prints when a call dies mid-frame, and nothing else.
#
# '^ERROR:' is ANCHORED, and that anchor is load-bearing. The engine prints its own runtime
# errors unindented at column 0; the tools print their own findings indented ("  ERROR: families
# .json: unexpected key"). Matching a bare 'ERROR:' would fail every run that legitimately
# reports data problems, which is the tool working. Matching '^ERROR:' catches the engine and
# leaves the tools alone.
#
# This was added after a real miss: a `%`-vs-`+` precedence bug made a print() throw
# "String formatting error: not all arguments converted", the engine logged it at column 0, the
# validator carried on and printed its own PASSED banner, and this wrapper reported success --
# the exact failure mode AGENTS §8a exists to prevent, one layer further in.
$patterns = @(
    'SCRIPT ERROR',
    'USER SCRIPT ERROR',
    'USER ERROR',
    'Parse Error',
    '^ERROR:',
    'String formatting error',
    'Invalid call',
    'Invalid access',
    'Invalid get index',
    'Invalid set index',
    'Trying to assign',
    'Attempt to call',
    'Cannot call method',
    'Condition ".*" is true'
)
$rx = ($patterns -join '|')
$errors = $lines | Where-Object { $_ -match $rx }

$shown = $lines
if ($Quiet) { $shown = $lines | Where-Object { $_ -notmatch '^\s*\[(trace|map)\]' } }
$shown | ForEach-Object { Write-Output $_ }

if ($errors.Count -gt 0) {
    # unique-by-message, because one bad frame can print the same error many times over
    $uniq = $errors | ForEach-Object { $_.Trim() } | Sort-Object -Unique
    Write-Output ''
    Write-Output ("RUNTIME ERRORS: {0} line(s), {1} distinct - this run does NOT pass." `
        -f $errors.Count, $uniq.Count)
    $uniq | Select-Object -First 20 | ForEach-Object { Write-Output ("  {0}" -f $_) }
    exit 1
}

exit $code
