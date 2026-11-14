<#
  Test-AssertMemorySources.ps1

  Suite for automation/verification/Assert-MemorySources.ps1.

  The cases that matter most are in Group 2: prove the detector FIRES when the source
  moves - by a new commit, by an edit nobody committed yet, by deletion. A gate that never
  accuses stays green forever.

  Group 4 is the other half, and the one that is easy to get backwards: a source that
  cannot be measured on this machine (repository absent, commit unknown) must NOT become a
  finding. "Did not run" painted as "failed" is family 2 in reverse, and on a store shared
  by two machines it would be red on one of them for ever.

  Hermetic: every repository is created in the temp folder, with a fixture identity passed
  on the command line. The gate runs as a child process, the way a CI step invokes it, so
  the exit code is the real one.
#>
[CmdletBinding()]
param([string]$GatePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($GatePath)) {
    $GatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\verification\Assert-MemorySources.ps1'
}
$script:Pass = 0
$script:Fail = 0
$script:Temps = New-Object 'System.Collections.ArrayList'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$BT = [string][char]96

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

function New-TempDir([string] $Prefix) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ($Prefix + '-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $null = $script:Temps.Add($dir)
    return $dir
}

# A store holding one memory whose body is the given lines.
function New-Store([string[]] $Lines) {
    $dir = New-TempDir 'memsrc-store'
    [IO.File]::WriteAllText((Join-Path $dir 'm.md'), (($Lines -join "`n") + "`n"), $Utf8NoBom)
    return $dir
}

# A code span, built without a literal backtick so this file is not hostage to its own
# delimiter.
function Span([string] $Text) { return $BT + $Text + $BT }
function Decl([string] $Path, [string] $Commit) { return '- mirrors: ' + (Span ("source: $Path @ $Commit")) }

function Invoke-FxGit([string] $Dir, [string[]] $GitArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = $null
        $o = (& git -C $Dir -c init.defaultBranch=main -c user.name=fixture -c user.email=fixture@example.com -c core.autocrlf=false @GitArgs 2>&1 | Out-String)
        $code = $global:LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    if ($code -ne 0) { throw "git $($GitArgs -join ' ') exited $code in ${Dir}: $o" }
    return ([string]$o).Trim()
}

function New-SourceRepo([string] $Prefix) {
    $dir = New-TempDir $Prefix
    $null = Invoke-FxGit $dir @('init', '-q')
    return $dir
}

function Set-Committed([string] $Dir, [string] $Rel, [string] $Text, [string] $Message) {
    $full = Join-Path $Dir $Rel
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($full, $Text, $Utf8NoBom)
    $null = Invoke-FxGit $Dir @('add', '-A')
    $null = Invoke-FxGit $Dir @('commit', '-q', '-m', $Message)
    return (Invoke-FxGit $Dir @('rev-parse', 'HEAD'))
}

try {
    Assert-True 'the gate exists' (Test-Path -LiteralPath $GatePath -PathType Leaf)
    if (-not (Test-Path -LiteralPath $GatePath -PathType Leaf)) { throw 'gate missing' }
    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required to run this suite' }

    $src = New-SourceRepo 'memsrc-repo'
    $doc = Join-Path $src 'docs\protocol.md'
    $sha1 = Set-Committed $src 'docs\protocol.md' "rev 1.0`n" 'rev 1.0'
    $short = $sha1.Substring(0, 7)
    $storeDoc = New-Store @((Decl $doc $sha1))
    $storeDir = New-Store @((Decl (Join-Path $src 'docs') $sha1))

    Write-Output ''
    Write-Output 'Group 1 - state 0: the source is what it was at the declared commit'
    $r = Invoke-Gate @('-MemoryRoot', $storeDoc)
    Assert-True 'unchanged source exits 0' ($r.Exit -eq 0) $r.Out
    Assert-True 'and the summary counts it as current (evidence that it MEASURED)' ($r.Out -match '1 source declaration\(s\): 1 current, 0 not measurable') $r.Out
    Assert-True 'and it prints OK (evidence, not only an exit code)' ($r.Out -match 'OK\s+no measured source has changed') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl $doc $short))))
    Assert-True 'an abbreviated commit (7 hex) measures too' ($r.Exit -eq 0 -and $r.Out -match '1 current') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', $storeDir)
    Assert-True 'a FOLDER as source, unchanged, exits 0' ($r.Exit -eq 0 -and $r.Out -match '1 current') $r.Out

    Write-Output ''
    Write-Output 'Group 2 - state 1: the source moved (the reason the gate exists)'
    [IO.File]::WriteAllText($doc, "rev 1.0`nerratum being typed`n", $Utf8NoBom)
    $r = Invoke-Gate @('-MemoryRoot', $storeDoc)
    Assert-True 'an edit not yet committed fails with exit 1' ($r.Exit -eq 1) $r.Out
    Assert-True 'and the finding says the change is not committed' ($r.Out -match 'has changed since \(a change not yet committed') $r.Out
    $sha2 = Set-Committed $src 'docs\protocol.md' "rev 1.1 with erratum`n" 'rev 1.1'
    $r = Invoke-Gate @('-MemoryRoot', $storeDoc)
    Assert-True 'a new commit on the source fails with exit 1' ($r.Exit -eq 1) $r.Out
    Assert-True 'the finding names the memory, the source, the declared commit and how far behind' ($r.Out -match 'FAIL\s+m\.md: checked against .*protocol\.md at commit [0-9a-f]{40}, and the source has changed since \(1 commit\(s\) later') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', $storeDir)
    Assert-True 'a FOLDER as source fails when a file inside it changes' ($r.Exit -eq 1 -and $r.Out -match 'has changed since') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl $doc $sha2))))
    Assert-True 'rewriting the commit after checking clears the finding' ($r.Exit -eq 0 -and $r.Out -match '1 current') $r.Out
    Remove-Item -LiteralPath $doc -Force
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl $doc $sha2))))
    Assert-True 'a source deleted from the working tree fails as a change' ($r.Exit -eq 1 -and $r.Out -match 'has changed since') $r.Out

    Write-Output ''
    Write-Output 'Group 3 - state 1: the declaration itself is false or unreadable'
    $null = Set-Committed $src 'docs\later.md' "born later`n" 'later'
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl (Join-Path $src 'docs\later.md') $sha1))))
    Assert-True 'a commit that does not contain the declared path fails' ($r.Exit -eq 1 -and $r.Out -match 'declares a source that commit [0-9a-f]{40} does not contain') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl (Join-Path $src 'docs\later.md') 'abc'))))
    Assert-True 'a malformed declaration (commit too short) fails rather than passing in silence' ($r.Exit -eq 1 -and $r.Out -match 'malformed source declaration') $r.Out

    Write-Output ''
    Write-Output 'Group 4 - not measurable is NOT a finding (never exit 1)'
    $srcSpace = New-SourceRepo 'memsrc repo with space'
    $shaS = Set-Committed $srcSpace 'my doc.md' "x`n" 'x'
    $spaced = Join-Path $srcSpace 'my doc.md'
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl $spaced $shaS))))
    Assert-True 'a path with spaces measures and exits 0 (it does not break at the space)' ($r.Exit -eq 0 -and $r.Out -match '1 current') $r.Out
    $absent = Join-Path ([IO.Path]::GetTempPath()) ('memsrc-absent-' + [guid]::NewGuid().ToString('N'))
    $absentDecl = Decl (Join-Path $absent 'docs\x.md') $sha1
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl $spaced $shaS), $absentDecl)))
    Assert-True 'a source whose repository is absent does not fail the run' ($r.Exit -eq 0) $r.Out
    Assert-True 'but it prints WARN and is counted (it does not vanish into the green)' ($r.Out -match 'WARN\s+m\.md: source NOT MEASURABLE' -and $r.Out -match '1 current, 1 not measurable') $r.Out
    $unknown = Decl $spaced '0123456789abcdef0123456789abcdef01234567'
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl $spaced $shaS), $unknown)))
    Assert-True 'a commit unknown to the clone does not fail the run, and warns' ($r.Exit -eq 0 -and $r.Out -match 'unknown to this clone' -and $r.Out -match '1 not measurable') $r.Out
    # Prose BETWEEN two code spans is not a span: the tick that closes one and the tick that
    # opens the next do not delimit a declaration. Read as one, this line would be a
    # malformed declaration and fail the run.
    $between = '- see ' + (Span 'a') + " source: $spaced @ abc " + (Span 'b')
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @((Decl $spaced $shaS), $between)))
    Assert-True 'prose between two code spans is not read as a declaration' ($r.Exit -eq 0 -and $r.Out -match '1 source declaration\(s\): 1 current') $r.Out

    Write-Output ''
    Write-Output 'Group 5 - state 2: could not verify (never 0, never 1)'
    $r = Invoke-Gate @()
    Assert-True 'no -MemoryRoot exits 2' ($r.Exit -eq 2 -and $r.Out -match 'COULD NOT VERIFY') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', (Join-Path $absent 'nowhere'))
    Assert-True 'a memory root that does not exist exits 2' ($r.Exit -eq 2) $r.Out
    $r = Invoke-Gate @('-MemoryRoot', (New-TempDir 'memsrc-empty'))
    Assert-True 'a store with no .md exits 2' ($r.Exit -eq 2) $r.Out
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @('- nothing declared here', ('- the word alone: ' + (Span 'source: the vendor spreadsheet')))))
    Assert-True 'a store with no declaration exits 2, not 0 (an empty sweep is not a clean sweep)' ($r.Exit -eq 2 -and $r.Out -match 'no source declaration') $r.Out
    Assert-True 'and a code span with the word but no path was not taken for a declaration' ($r.Out -match '0 source declaration\(s\)') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', (New-Store @($absentDecl)))
    Assert-True 'when not one declared source is measurable the answer is 2, not 0' ($r.Exit -eq 2 -and $r.Out -match 'not one declared source is measurable') $r.Out
}
finally {
    $leftovers = @()
    foreach ($d in $script:Temps) {
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $d) { $leftovers += $d }
    }
    if ($leftovers.Count -gt 0) {
        Write-Output ("  WARN  {0} fixture(s) NOT removed: {1}" -f $leftovers.Count, ($leftovers -join '; '))
    }
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
