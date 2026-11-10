<#
  PreToolUse hook (Bash): advisory warning when a command carries a backslash
  through a transport that rewrites it.

  On some hosts the Bash tool collapses a doubled backslash into a single one, and
  escapes such as backslash-n inside a heredoc or an inline script (python -c,
  node -e, printf) reach the interpreter rewritten. cmd.exe /c is a fourth
  transport: a backslash-t in a .cmd path became a TAB, cmd went interactive, read
  EOF and exited 0 having run nothing. The rule ("a string that crosses a layer is
  rewritten silently") was written down in one practice and kept recurring anyway -
  nine log entries in two weeks, most with the rule already in context. The failure
  is choosing the transport by habit, not missing knowledge, so this hook puts the
  reminder at the moment of choice.

  Advisory by design: always exit 0. A malformed event, or a command without the
  pattern, produces no output. ASCII-only for Windows PowerShell 5.1; the
  backslash is built from its code point so this file never depends on how a
  transport treats one.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
    $event = $raw | ConvertFrom-Json -ErrorAction Stop
    $command = [string] $event.tool_input.command
} catch {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

$bs = [string][char]92
if (-not $command.Contains($bs)) { exit 0 }

# Transports that rewrite: a heredoc body, an inline interpreter script, printf.
$heredoc = $command -match '<<-?\s*[''"]?[A-Za-z_]+'
$inline  = $command -match '(?i)(^|[\s;&|(])(python[0-9.]*|py|node|perl|ruby|pwsh|powershell)(\.exe)?\b[^;&|]*\s-(c|e|Command)\s'
$printf  = $command -match '(^|[\s;&|(])printf\s'
# cmd.exe /c, or a .cmd/.bat path, with a backslash: the exit 0 of a cmd that ran
# nothing reads as a green check. Run .cmd/.bat via the PowerShell tool instead.
$cmdexe  = $command -match '(?i)(^|[\s;&|(])cmd(\.exe)?\s+/[cCkK]\b' -or $command -match '(?i)\.(cmd|bat)\b'
if (-not ($heredoc -or $inline -or $printf -or $cmdexe)) { exit 0 }

$via = @()
if ($heredoc) { $via += 'heredoc' }
if ($inline)  { $via += 'script inline (-c/-e)' }
if ($printf)  { $via += 'printf' }
if ($cmdexe)  { $via += 'cmd.exe /c or a .cmd/.bat path (use the PowerShell tool)' }

$message = (
    '[bash-backslash] This command carries a backslash through {0} in the Bash tool. ' +
    'The transport can collapse a doubled backslash and rewrite escapes such as backslash-n. ' +
    'If the backslash matters, write the script to a file and run the file; build a literal ' +
    'backslash from its code point (chr(92)). After running, check the output is what you ' +
    'expected before moving on. Advisory, not a block.'
) -f ($via -join ', ')

$output = @{
    hookSpecificOutput = @{
        hookEventName = 'PreToolUse'
        additionalContext = $message
    }
}
$output | ConvertTo-Json -Depth 4 -Compress
exit 0
