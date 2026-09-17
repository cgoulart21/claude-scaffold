<#
  PreToolUse hook: block destructive Git operations for Bash and PowerShell.

  Reads the hook event from stdin. Exit 2 blocks the tool call; exit 0 allows it.
  ASCII-only and dependency-free for Windows PowerShell 5.1.

  The list below is the whole contract. A guardrail is worth exactly what it
  enumerates, so read it as a list of what is covered rather than a promise that
  destructive git is impossible - and add your own entries rather than assuming
  the domain is handled.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    # Discard anything before the opening brace. ConvertFrom-Json rejects a leading byte
    # order mark, and the rejection comes out shaped like the defect this hook hunts
    # ("blocked") rather than like "I could not read this" - which turns a guardrail into
    # a wall that stops everything, including what it was meant to allow.
    #
    # Trimming U+FEFF is NOT enough: stdin is decoded in the console code page, so the
    # BOM's three bytes usually arrive as three unrelated characters and never match the
    # character you were looking for. Find the brace instead of guessing the decoding.
    $start = $raw.IndexOf('{')
    if ($start -gt 0) { $raw = $raw.Substring($start) }
    $hookEvent = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    # A guardrail that cannot read its event must not wave the command through.
    [Console]::Error.WriteLine('BLOCKED: the Git guardrail could not parse the PreToolUse event.')
    exit 2
}

if ($hookEvent.hook_event_name -ne 'PreToolUse' -or
    $hookEvent.tool_name -notin @('Bash', 'PowerShell') -or
    $null -eq $hookEvent.tool_input -or
    -not ($hookEvent.tool_input -is [System.Management.Automation.PSCustomObject]) -or
    -not ($hookEvent.tool_input.command -is [string]) -or
    [string]::IsNullOrWhiteSpace($hookEvent.tool_input.command)) {
    [Console]::Error.WriteLine('BLOCKED: invalid Bash or PowerShell PreToolUse event.')
    exit 2
}
$command = $hookEvent.tool_input.command

# Matches git, git.exe, call-operator prefixes, and quoted or unquoted paths.
$gitPrefix = "(?i)(^|[\s&|;(<>)])(?:(?:[`"'][^`"']*[\\/])|(?:[^\s;&|<>]*[\\/])|[`"'])?git(?:\.exe)?[`"']?\s+"
$boundary = '(?:[=\s;&|<>()]|$)'
$dangerous = @(
    @{ Name = 'force push'; Pattern = 'push\b[^;&|<>]*["'']?(?:--force(?:-with-lease)?|-[a-z]*f[a-z]*)["'']?' + $boundary }
    @{ Name = 'force push refspec'; Pattern = 'push\b[^;&|]*\s["'']?\+[^\s;&|]+' }
    @{ Name = 'hard reset'; Pattern = 'reset\b[^;&|<>]*["'']?--hard["'']?' + $boundary }
    @{ Name = 'forced clean'; Pattern = 'clean\b[^;&|<>]*(?:--force|-[a-z]*f[a-z]*)' + $boundary }
    @{ Name = 'forced branch delete'; Pattern = 'branch\b[^;&|<>]*(?:(?-i:-D)\b|-[a-z]*d[a-z]*f[a-z]*\b|-[a-z]*f[a-z]*d[a-z]*\b|(?:--delete|-[a-z]*d[a-z]*)\b[^;&|<>]*(?:--force|-[a-z]*f[a-z]*)\b|(?:--force|-[a-z]*f[a-z]*)\b[^;&|<>]*(?:--delete|-[a-z]*d[a-z]*)\b)' }
    @{ Name = 'checkout all'; Pattern = 'checkout\b[^;&|<>]*(?:\s--)?\s+["'']?\.["'']?' + $boundary }
    @{ Name = 'restore all'; Pattern = 'restore\b[^;&|<>]*(?:\s--)?\s+["'']?\.["'']?' + $boundary }
)

foreach ($item in $dangerous) {
    # Allow Git global options such as -C before the actual subcommand.
    if ([regex]::IsMatch($command, $gitPrefix + '[^;&|]*?' + $item.Pattern)) {
        [Console]::Error.WriteLine("BLOCKED: dangerous Git operation matched '$($item.Name)'.")
        exit 2
    }
}

exit 0
