<#
  Test-AssertMemoryIndex.ps1

  Suite for automation/verification/Assert-MemoryIndex.ps1.

  The case that matters most is Group 1: prove the detector FIRES when an index hook is
  not the memory's description. A gate that never accuses stays green forever. The other
  groups cover each finding the contract names, the usage errors (exit 2, never 0), and
  the parser in front of the two inputs that fooled earlier measurements in the practice
  this came from: a title with brackets inside it, and an index written with CRLF.

  Hermetic: no case reads a real memory store. The gate runs as a child process, the way
  a CI step invokes it, so the exit code is the real one.
#>
[CmdletBinding()]
param([string]$GatePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($GatePath)) {
    $GatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\verification\Assert-MemoryIndex.ps1'
}
$script:Pass = 0
$script:Fail = 0
$script:Temps = New-Object 'System.Collections.ArrayList'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$EmDash = [string][char]0x2014
$EnDash = [string][char]0x2013

function Invoke-Gate {
    param([string[]] $ScriptArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = $null
        $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $GatePath @ScriptArgs 2>&1 | Out-String)
        $code = $global:LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Exit = $code; Out = $out }
}

function Assert-True {
    param([string] $Name, [bool] $Condition, [string] $Detail)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else { $script:Fail++; Write-Output "  FAIL  $Name"; if ($Detail) { Write-Output "          -> $Detail" } }
}

function New-Memory {
    # One minimal memory: frontmatter plus body. -NoDescription omits the key.
    param([string] $Name, [string] $Description, [switch] $NoDescription)
    $lines = @('---', "name: $Name")
    if (-not $NoDescription) { $lines += "description: $Description" }
    $lines += @('metadata:', '  type: reference', '---', '', "Body of $Name.")
    return ($lines -join "`n") + "`n"
}

function New-Line {
    # One index line, with the requested separator between the link and the hook.
    param([string] $Title, [string] $File, [string] $Hook, [string] $Dash = '-')
    return "- [$Title]($File) $Dash $Hook"
}

function New-Fixture {
    # $Files: file name -> memory text. $Index: the lines of MEMORY.md under a heading. -NoIndex writes no index.
    param([hashtable] $Files, [string] $Index, [switch] $NoIndex)
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('memidx-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $null = $script:Temps.Add($dir)
    foreach ($k in $Files.Keys) { [IO.File]::WriteAllText((Join-Path $dir $k), $Files[$k], $Utf8NoBom) }
    if (-not $NoIndex) {
        [IO.File]::WriteAllText((Join-Path $dir 'MEMORY.md'), ("# Memory index`n`n## Tool gotchas`n`n" + $Index + "`n"), $Utf8NoBom)
    }
    return $dir
}

$descA = 'When command X fails silently on host Y; the cause is Z and the way out is W.'
$descB = 'When you need the path of tool B; it lives under C and needs flag D.'

try {
    Assert-True 'the gate exists' (Test-Path -LiteralPath $GatePath -PathType Leaf) $GatePath
    if (-not (Test-Path -LiteralPath $GatePath -PathType Leaf)) { throw 'gate missing' }

    Write-Output 'Group 1 - the detector FIRES when the hook is not the description'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index (New-Line 'A' 'a.md' 'a hook written apart from the description')
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a divergent hook fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'the output names the memory and the reason' ($r.Out -match 'a\.md' -and $r.Out -match 'differs') $r.Out
    Assert-True 'no OK line in the output' ($r.Out -notmatch '(?m)^OK ') $r.Out

    Write-Output 'Group 2 - a clean set passes, and the sweep is counted'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA); 'b.md' = (New-Memory 'b' $descB) } -Index ((New-Line 'A' 'a.md' $descA) + "`n" + (New-Line 'B' 'b.md' $descB))
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a consistent index passes (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'the output counts 2 memory files and 2 index lines' ($r.Out -match '2 memory file' -and $r.Out -match '2 index line') $r.Out
    Assert-True 'and states the cap in use' ($r.Out -match '200') $r.Out
    Assert-True 'and prints OK' ($r.Out -match 'OK\s+every index hook') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', $d, '-Quiet')
    Assert-True '-Quiet: passes and prints nothing' ($r.Exit -eq 0 -and [string]::IsNullOrWhiteSpace($r.Out)) $r.Out

    Write-Output 'Group 3 - a memory with NO line in the index fails'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA); 'b.md' = (New-Memory 'b' $descB) } -Index (New-Line 'A' 'a.md' $descA)
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a memory without a line fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'and b.md is named as not in the index' ($r.Out -match 'b\.md' -and $r.Out -match 'not in the index') $r.Out

    Write-Output 'Group 4 - an index line whose file does not exist fails'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index ((New-Line 'A' 'a.md' $descA) + "`n" + (New-Line 'Z' 'ghost.md' 'points at a file that is not there'))
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a line for a missing file fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'and ghost.md is named as missing' ($r.Out -match 'ghost\.md' -and $r.Out -match 'does not exist') $r.Out

    Write-Output 'Group 5 - a DUPLICATE line fails'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index ((New-Line 'A' 'a.md' $descA) + "`n" + (New-Line 'A again' 'a.md' $descA))
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'two lines for one memory fail (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'and the output says duplicate' ($r.Out -match 'duplicate') $r.Out

    Write-Output 'Group 6 - a description over the cap fails, and the cap is a parameter'
    $long = ('When X; ' + ('word ' * 45)).Trim()
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $long) } -Index (New-Line 'A' 'a.md' $long)
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True ("a description of {0} characters fails at cap 200 (exit 1)" -f $long.Length) ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'and the output states the length and the cap' ($r.Out -match ([string]$long.Length) -and $r.Out -match '200') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', $d, '-MaxLength', '500')
    Assert-True 'with -MaxLength 500 the same fixture passes (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 7 - a memory with no description fails'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' -NoDescription) } -Index (New-Line 'A' 'a.md' 'any hook')
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'frontmatter without description fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'and the output says no one-line description' ($r.Out -match 'no one-line description') $r.Out

    Write-Output 'Group 8 - the parser tolerates brackets INSIDE the title'
    # A naive parser stops at the first ] and reports the memory as not in the index.
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index (New-Line 'Guard [tag] fires' 'a.md' $descA)
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a title with brackets inside passes (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 9 - the three separators between link and hook are accepted'
    foreach ($sep in @(@{ Name = 'hyphen'; Dash = '-' }, @{ Name = 'em dash'; Dash = $EmDash }, @{ Name = 'en dash'; Dash = $EnDash })) {
        $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index (New-Line 'A' 'a.md' $descA -Dash $sep.Dash)
        $r = Invoke-Gate @('-MemoryRoot', $d)
        Assert-True ("separator {0} passes (exit 0)" -f $sep.Name) ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    }

    Write-Output 'Group 10 - the comparison is exact: case counts'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index (New-Line 'A' 'a.md' $descA.ToUpper())
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a hook equal up to case fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"

    Write-Output 'Group 11 - usage errors exit 2, never 0'
    $missing = Join-Path ([IO.Path]::GetTempPath()) ('memidx-missing-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $r = Invoke-Gate @('-MemoryRoot', $missing)
    Assert-True 'a missing root exits 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    $r = Invoke-Gate @()
    Assert-True 'no -MemoryRoot at all exits 2 and says it is required' ($r.Exit -eq 2 -and $r.Out -match 'required') $r.Out
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -NoIndex
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a root without MEMORY.md exits 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    $d = New-Fixture -Files @{} -Index ''
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a root with no memory file exits 2 (an empty sweep is not a clean sweep)' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 12 - the description must be a plain YAML scalar'
    # The host parses the frontmatter as YAML. A description with ": " becomes a mapping and
    # breaks the parse; wrapped in quotes, the text the parser returns is not the text in the
    # file, so the index (which repeats the file verbatim) would drift from what the host sees.
    foreach ($case in @(
        @{ Name = 'colon and space';           Desc = 'When X happens: the cause is Y.' },
        @{ Name = 'hash after a space';        Desc = 'When X happens #1, the cause is Y.' },
        @{ Name = 'wrapping double quotes';    Desc = '"When X happens, the cause is Y."' },
        @{ Name = 'leading bracket';           Desc = '[tag] when X happens, the cause is Y.' },
        @{ Name = 'leading hash';              Desc = '# when X happens, the cause is Y.' },
        @{ Name = 'trailing colon';            Desc = 'When X happens, the cause is Y:' })) {
        $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $case.Desc) } -Index (New-Line 'A' 'a.md' $case.Desc)
        $r = Invoke-Gate @('-MemoryRoot', $d)
        Assert-True ("a description with {0} fails (exit 1)" -f $case.Name) ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
        Assert-True ("and the output says plain YAML scalar ({0})" -f $case.Name) ($r.Out -match 'plain YAML scalar') $r.Out
    }
    # Control: a colon WITHOUT a space after it (a time, a URL) is allowed.
    $ok = 'When the clock reads 17:30 and the URL is https://example.org; the cause is Y.'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $ok) } -Index (New-Line 'A' 'a.md' $ok)
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'control: a colon without a space (time, URL) passes (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 13 - an invalid character in the file name is a FINDING, not an exception'
    # The line pattern accepts | and < in a name; Test-Path -LiteralPath throws on them under
    # Stop, and the script would exit 1 by exception - the same exit as a finding, with the
    # diagnosis lying. Assert-MemoryLinks paid this price first.
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index ((New-Line 'A' 'a.md' $descA) + "`n" + (New-Line 'Bad' 'a|b.md' 'hook'))
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a name with an invalid character fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'and fails as a readable FAIL naming the file, not a raw exception' ($r.Out -match 'FAIL' -and $r.Out -match 'invalid' -and $r.Out -notmatch 'Exception') $r.Out

    Write-Output 'Group 14 - a line with no separator between link and hook fails'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index ("- [A](a.md) " + $descA)
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a line without a separator fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'and the output says no separator' ($r.Out -match 'no separator') $r.Out

    Write-Output 'Group 15 - -Quiet with a finding prints the FAIL lines and the count, not the summary'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index (New-Line 'A' 'a.md' 'a divergent hook')
    $r = Invoke-Gate @('-MemoryRoot', $d, '-Quiet')
    Assert-True '-Quiet with a finding exits 1 and prints the FAIL and the count' ($r.Exit -eq 1 -and $r.Out -match 'FAIL' -and $r.Out -match 'problem') $r.Out
    Assert-True 'and does not print the memory: summary line' ($r.Out -notmatch '(?m)^memory:') $r.Out

    Write-Output 'Group 16 - an index written with CRLF reads like one written with LF'
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA); 'b.md' = (New-Memory 'b' $descB) } -NoIndex
    $crlf = "# Memory index`r`n`r`n## Tool gotchas`r`n`r`n" + (New-Line 'A' 'a.md' $descA) + "`r`n" + (New-Line 'B' 'b.md' $descB) + "`r`n"
    [IO.File]::WriteAllText((Join-Path $d 'MEMORY.md'), $crlf, $Utf8NoBom)
    $r = Invoke-Gate @('-MemoryRoot', $d)
    Assert-True 'a consistent CRLF index passes (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 17 - an unreadable memory file is COULD NOT VERIFY (exit 2), never a finding or a raw exception'
    # Under Stop, a ReadAllText that fails (a locked file) threw, and the script exited 1 by
    # exception - the same exit as a finding. The byte gate already wraps its body and exits 2.
    $d = New-Fixture -Files @{ 'a.md' = (New-Memory 'a' $descA) } -Index (New-Line 'A' 'a.md' $descA)
    $lock = [IO.File]::Open((Join-Path $d 'a.md'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try { $r = Invoke-Gate @('-MemoryRoot', $d) } finally { $lock.Dispose() }
    Assert-True 'a locked memory file exits 2, not 1' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'and the output says COULD NOT VERIFY, with no raw exception' ($r.Out -match 'COULD NOT VERIFY' -and $r.Out -notmatch 'Exception') $r.Out
}
finally {
    foreach ($d in $script:Temps) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
