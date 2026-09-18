<#
  Test-CheckNoPersonalData.ps1

  Exercises the gate against fixtures generated in a temp directory.
  Nothing planted is ever written inside the repository.
#>
[CmdletBinding()]
param(
    [string]$GatePath,
    [string]$PatternFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1: with [CmdletBinding()], $PSScriptRoot is EMPTY inside the
# param() block and populated in the body. Resolve defaults here, never up there.
if ([string]::IsNullOrEmpty($GatePath))    { $GatePath    = Join-Path $PSScriptRoot 'check-no-personal-data.ps1' }
if ([string]::IsNullOrEmpty($PatternFile)) { $PatternFile = Join-Path $PSScriptRoot 'patterns.txt' }

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else            { $script:Fail++; Write-Output "  FAIL  $Name" }
}

function Invoke-Gate {
    param([string]$Tree, [string]$Patterns)

    if ([string]::IsNullOrEmpty($Patterns)) { $Patterns = $PatternFile }

    # A missing gate must surface as a FAIL on every assertion, not as an exploding
    # suite: a suite that dies tells you nothing about which assertions were wrong.
    if (-not (Test-Path -LiteralPath $GatePath -PathType Leaf)) {
        return [pscustomobject]@{ Code = -1; Text = "gate not found: $GatePath" }
    }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $GatePath -Path $Tree -PatternFile $Patterns 2>&1
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join "`n") }
    }
    finally { $ErrorActionPreference = $previous }
}

function Join-Fragment {
    # The planted strings are assembled here at runtime, from fragments that match
    # nothing on their own. A complete offending literal in this file would be a hit
    # in the repository's own scan, and excluding this file from the gate would put a
    # hole in the very thing the gate claims to enumerate.
    param([string[]]$Part)
    return ($Part -join '')
}

function New-Tree {
    param([string]$Content, [string]$Name = 'sample.md')
    $dir = Join-Path $env:TEMP ('gate-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir $Name) -Value $Content -Encoding UTF8
    return $dir
}

Write-Output 'Group 1 - clean trees exit 0'

$clean = @(
    'Put the vault under C:\Projects\my-vault and never inside a synced folder.',
    'Deploy to C:\Users\<username>\.claude\skills',
    'Deploy to $env:USERPROFILE\.claude\skills',
    'Write to %USERNAME% home',
    'Contact the maintainer at you@example.com',
    'See C:\Path\To\your-repo for the checkout'
)
foreach ($line in $clean) {
    $tree = New-Tree -Content $line
    try {
        $result = Invoke-Gate -Tree $tree
        Assert-True "clean: $line" ($result.Code -eq 0)
    }
    finally { Remove-Item -LiteralPath $tree -Recurse -Force }
}

Write-Output 'Group 2 - each pattern fires'

$planted = @(
    @{ Id = 'win-user-path';  Text = (Join-Fragment @('The log lives in C:', '\Users\', 'jsmith\home')) },
    @{ Id = 'bash-user-path'; Text = (Join-Fragment @('Run cat /c/', 'Users/', 'jsmith/home')) },
    @{ Id = 'abs-drive-path'; Text = (Join-Fragment @('The repo is at D:', '\Work\internal-thing')) },
    @{ Id = 'email';          Text = (Join-Fragment @('Mail jane.doe', '@', 'somelab.edu for access')) },
    @{ Id = 'artifact-url';   Text = (Join-Fragment @('Read https://claude', '.ai/public/', 'artifact/abc123')) },
    @{ Id = 'session-silo';   Text = (Join-Fragment @('Check .claude', '/projects/', 'C--Work/memory')) }
)
foreach ($case in $planted) {
    $tree = New-Tree -Content $case.Text
    try {
        $result = Invoke-Gate -Tree $tree
        Assert-True "fires: $($case.Id)"      ($result.Code -eq 1)
        Assert-True "reports id: $($case.Id)" ($result.Text -like "*$($case.Id)*")
    }
    finally { Remove-Item -LiteralPath $tree -Recurse -Force }
}

Write-Output 'Group 3 - usage errors exit 2, never 0'

$tree = New-Tree -Content 'harmless'
try {
    $missing = Join-Path $env:TEMP ('nope-' + [guid]::NewGuid().ToString('N') + '.txt')
    Assert-True 'missing pattern file exits 2' ((Invoke-Gate -Tree $tree -Patterns $missing).Code -eq 2)

    $empty = Join-Path $tree 'empty-patterns.txt'
    Set-Content -LiteralPath $empty -Value '# only a comment' -Encoding UTF8
    Assert-True 'empty pattern file exits 2' ((Invoke-Gate -Tree $tree -Patterns $empty).Code -eq 2)
}
finally { Remove-Item -LiteralPath $tree -Recurse -Force }

Write-Output 'Group 4 - binary and .git are skipped'

$tree = New-Tree -Content 'harmless'
try {
    $gitDir = Join-Path $tree '.git'
    New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
    $planted = Join-Fragment @('C:', '\Users\', 'jsmith\x')
    Set-Content -LiteralPath (Join-Path $gitDir 'COMMIT_EDITMSG') -Value $planted -Encoding UTF8
    [IO.File]::WriteAllBytes((Join-Path $tree 'blob.png'), [byte[]](0, 1, 2, 3))
    $result = Invoke-Gate -Tree $tree
    Assert-True '.git and binaries ignored' ($result.Code -eq 0)
}
finally { Remove-Item -LiteralPath $tree -Recurse -Force }

Write-Output 'Group 5 - the gate ships ASCII-only and parses on 5.1'

foreach ($file in @($GatePath, $PatternFile, $PSCommandPath)) {
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        $nonAscii = @([IO.File]::ReadAllBytes($file) | Where-Object { $_ -gt 127 }).Count
        Assert-True "ascii-only: $(Split-Path -Leaf $file)" ($nonAscii -eq 0)
    }
    else {
        Assert-True "ascii-only: $(Split-Path -Leaf $file) (file missing)" $false
    }
}

if (Test-Path -LiteralPath $GatePath -PathType Leaf) {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($GatePath, [ref]$null, [ref]$parseErrors) | Out-Null
    Assert-True 'gate parses without errors' ($null -eq $parseErrors -or $parseErrors.Count -eq 0)
}
else {
    Assert-True 'gate parses without errors (file missing)' $false
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
