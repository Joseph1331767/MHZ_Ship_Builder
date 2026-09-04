# PreToolUse guard: blocks secret-file access and dangerous commands.
# Exit 2 = block (stderr is fed back to the agent). Anything else = allow.
$ErrorActionPreference = 'SilentlyContinue'

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $hook = $raw | ConvertFrom-Json } catch { exit 0 }

$tool = $hook.tool_name

# Protected file patterns (secrets)
$blockedFile = '(^|[\\/])\.env($|\.)|[\\/]secrets[\\/]|\.pem$|\.key$|(^|[\\/])credentials'

# Dangerous command patterns
$blockedCmd = 'git\s+push\b.*(\s--force\b|\s-f\b)|rm\s+-rf\s+([/~]|\.git)|--no-verify\b|Remove-Item\s+.*-Recurse.*\s(\.git|[A-Z]:[\\/]\s*$)'

if ($tool -in @('Read', 'Edit', 'Write', 'NotebookEdit')) {
    $path = $hook.tool_input.file_path
    if ($path -and ($path -match $blockedFile)) {
        [Console]::Error.WriteLine("BLOCKED by guard.ps1: '$path' matches a protected secret pattern. Secrets must stay out of agent context (AGENTS.md).")
        exit 2
    }
}
elseif ($tool -in @('Bash', 'PowerShell')) {
    $cmd = $hook.tool_input.command
    if ($cmd) {
        if ($cmd -match $blockedCmd) {
            [Console]::Error.WriteLine("BLOCKED by guard.ps1: command matches a dangerous pattern (force-push / recursive delete / --no-verify).")
            exit 2
        }
        if (($cmd -match '(^|[\s\\/])\.env\b') -and ($cmd -match '\b(cat|type|Get-Content|gc|more|less|Select-String|findstr)\b')) {
            [Console]::Error.WriteLine("BLOCKED by guard.ps1: reading .env via shell is not allowed.")
            exit 2
        }
    }
}

exit 0
