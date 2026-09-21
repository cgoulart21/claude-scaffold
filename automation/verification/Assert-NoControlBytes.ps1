<#
  Assert-NoControlBytes.ps1

  Gate: no text file under the root carries a corrupting control byte.

  WHY IT EXISTS. In a non-raw string literal in most languages, `\a` `\b` `\f` `\v`
  are VALID escapes: they emit BEL, backspace, form feed and vertical tab, raise no
  warning, and corrupt the file silently. Windows paths are where it bites - a path
  ending in `\tools\analysis` becomes TAB, `ools`, BEL, `nalysis`, unfollowable and
  almost right. The natural rule ("sweep after appending to the log") is too narrow:
  in one practice the rule was prose only, scoped to append-only files, and on the
  day this gate was written it found two latent bytes in files that rule never
  reached - a memory note and a script. Sweep ALL tracked text.

  WHAT IT REPORTS. file:line and the byte's name. The position is what makes it
  findable; a filename alone sends you reading the whole file with cat -A.

  WHAT IT LEAVES ALONE. 0x09 (TAB) and 0x0A - legitimate in text. Accept the cost:
  `\t` corrupts a path the same way and a TAB is indistinguishable from an intended
  one. The gate is worth what it enumerates.

  AND THE LONE CR. 0x0D is legitimate only as half of CRLF. Not followed by 0x0A - or
  the last byte of the file - it is the residue of an insertion into a CRLF file
  followed by a normalisation to LF, and it hides: a stray CR at the start of a line
  made that line invisible to every ^-anchored parser and to cat itself, and the first
  version of this gate reported the file clean because 0x0D was off its list (a gate
  over the memory index caught it instead). A file with bare-CR line endings now fails
  on every line, one finding per line; if you keep one on purpose, -KnownException is
  where it goes. Both trees this gate first ran on were measured lone-CR-free by a byte
  scan before the rule changed, so the finding was not born red.

  EXIT CONTRACT (three states):
    0  scanned, no control byte and no lone CR found
    1  scanned and FOUND one or more (each printed as FAIL file:line byte)
    2  could NOT verify (root missing, no eligible text file)
  No break path reaches 1: an unreadable file is reported and skipped, never
  counted as a finding - a finding nobody measured is invented.

  PARAMETERS
    -Root            Directory to sweep. Default: the repository this file lives in.
    -KnownException  Relative paths declared as legitimate carriers of a control byte.
                     Empty by default; each entry needs a reason next to it in the caller.
    -NoKnownException Ignore any exception list. Exists because passing an empty string
                     through `powershell -File` does not survive the parameter binder.
    -ExcludeDir      Directory names never descended into. Default: .git node_modules
                     build dist.
#>
[CmdletBinding()]
param(
    [string]   $Root,
    [string[]] $KnownException = @(),
    [switch]   $NoKnownException,
    [string[]] $ExcludeDir = @('.git', 'node_modules', 'build', 'dist')
)

$ErrorActionPreference = 'Stop'

function Write-Finding([string] $Text) { Write-Output "FAIL  $Text" }

try {
    if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        Write-Output "COULD NOT VERIFY: root does not exist: $Root"
        exit 2
    }
    # Get-Item, not Resolve-Path: it returns the canonical long form. With the root in
    # 8.3 form and the children in long form, a Substring cut in the wrong place and the
    # finding named the wrong path - a well-formed finding pointing at the wrong target.
    $Root = (Get-Item -LiteralPath $Root).FullName

    $bad  = @{ 0 = 'NUL'; 7 = 'BEL'; 8 = 'BS'; 11 = 'VT'; 12 = 'FF' }
    $exts = @('.md', '.ps1', '.psm1', '.psd1', '.py', '.txt', '.json', '.yml', '.yaml', '.toml', '.cfg', '.sh', '.gitignore', '.gitattributes', '.template')
    $excludeRx = '[\\/](' + (($ExcludeDir | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')[\\/]'

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch $excludeRx -and
            ($exts -contains $_.Extension.ToLowerInvariant() -or $exts -contains $_.Name.ToLowerInvariant())
        })

    if ($files.Count -eq 0) {
        Write-Output "COULD NOT VERIFY: no eligible text file under $Root"
        exit 2
    }

    $exceptions = if ($NoKnownException) { @() } else { @($KnownException | Where-Object { $_ }) }
    $findings = 0
    $exempt = 0

    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/')
        if ($exceptions -contains $rel) { $exempt++; continue }
        try { $bytes = [System.IO.File]::ReadAllBytes($f.FullName) } catch {
            Write-Output "WARNING  $rel could not be read: $($_.Exception.Message)"
            continue
        }
        # One pass, counting newlines, so the report says LINE and not just file.
        $line = 1
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            $b = $bytes[$i]
            if ($b -eq 10) { $line++; continue }
            if ($b -eq 13) {
                # CR is legitimate only as half of CRLF; on its own it is a finding (see the
                # header). And it ENDS a line: the counter advances after the finding, or a
                # bare-CR file reports every finding on line 1.
                if (($i + 1) -ge $bytes.Length -or $bytes[$i + 1] -ne 10) {
                    Write-Finding ("{0}:{1} lone CR (0x0D not followed by 0x0A)" -f $rel, $line)
                    $findings++
                    $line++
                }
                continue
            }
            if ($bad.ContainsKey([int]$b)) {
                Write-Finding ("{0}:{1} control byte {2} (0x{3})" -f $rel, $line, $bad[[int]$b], $b.ToString('X2'))
                $findings++
            }
        }
    }

    $summary = "scanned {0} text file(s) under {1}" -f $files.Count, $Root
    if ($exempt -gt 0) { $summary += " | $exempt declared exception(s)" }
    Write-Output $summary

    if ($findings -gt 0) {
        Write-Output "$findings control byte(s) found. Repair the byte ALONE - never rewrite the file, and verify the intended value before writing it."
        exit 1
    }
    Write-Output 'OK  no control byte 0x00/07/08/0B/0C and no lone CR.'
    exit 0
}
catch {
    # A break must never exit 1: 1 means "found a byte", and confusing the two is the
    # exact defect the exit-code contract exists to prevent.
    Write-Output "COULD NOT VERIFY: $($_.Exception.Message)"
    exit 2
}
