<#
  Test-BackupPushClassification.ps1

  Exercises the push-failure classification in automation/maintenance/backup-config.ps1
  against the output git really emits in each mode.

  WHY IT READS THE REGEXES OUT OF THE SCRIPT instead of carrying copies: a test that
  restates the rule it should verify keeps passing while the artifact's rule changes
  underneath it. Here the three regexes are extracted from the script's own text; edit
  the script and this test exercises the edited version, and if the anchors vanish it
  FAILS instead of reporting there was nothing to test.

  WHY IT EXISTS. Twice in one day the script reported "check the network" for a
  failure that was history divergence - another machine had pushed first. The
  classification was fixed; this test fixes the contract, including the ORDER of the
  cascade, which is contract too: reordering the elseifs would otherwise leave a
  source-reading test passing over a cascade that no longer exists.
#>
[CmdletBinding()]
param([string]$ScriptPath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($ScriptPath)) {
    $ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\maintenance\backup-config.ps1'
}
$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string] $Name, [bool] $Condition, [string] $Detail = '')
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else { $script:Fail++; Write-Output "  FAIL  $Name"; if ($Detail) { Write-Output "          -> $Detail" } }
}

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    Write-Output "FAIL  backup-config.ps1 not found at $ScriptPath"
    Write-Output 'PASS 0  FAIL 1'
    exit 1
}
$text = Get-Content -LiteralPath $ScriptPath -Raw

Write-Output 'Group 1 - the classification anchors exist in the script'
$patterns = [ordered] @{
    DIVERGENCE     = 'non-fast-forward'
    NETWORK        = 'Could not resolve host'
    AUTHENTICATION = 'Authentication failed'
}
$regex = [ordered] @{}
foreach ($k in $patterns.Keys) {
    $anchor = [regex]::Escape($patterns[$k])
    $m = [regex]::Match($text, "-match\s+'([^']*" + $anchor + "[^']*)'")
    Assert-True ("classifier {0} present in the script" -f $k) $m.Success ("no -match with the anchor '{0}'" -f $patterns[$k])
    if ($m.Success) { $regex[$k] = $m.Groups[1].Value }
}
if ($script:Fail -gt 0) {
    Write-Output ''
    Write-Output "PASS $script:Pass  FAIL $script:Fail"
    Write-Output '  (aborted: without the anchors there is nothing to exercise)'
    exit 1
}

Assert-True 'the script prints the raw output in the unclassified case' ($text -match 'NOT CLASSIFIED')
Assert-True 'the script denies the network explicitly on divergence' ($text -match 'NOT the network')

$posDiv  = $text.IndexOf($regex['DIVERGENCE'],     [StringComparison]::Ordinal)
$posNet  = $text.IndexOf($regex['NETWORK'],        [StringComparison]::Ordinal)
$posAuth = $text.IndexOf($regex['AUTHENTICATION'], [StringComparison]::Ordinal)
Assert-True 'DIVERGENCE is tested BEFORE network' ($posDiv -gt 0 -and $posDiv -lt $posNet) "div=$posDiv net=$posNet"
Assert-True 'NETWORK is tested BEFORE authentication' ($posNet -gt 0 -and $posNet -lt $posAuth) "net=$posNet auth=$posAuth"
Assert-True 'the NOT CLASSIFIED fallback comes after all three' ($text.IndexOf('NOT CLASSIFIED', [StringComparison]::Ordinal) -gt $posAuth)

function Classify([string] $pushOut) {
    if ($pushOut -match $regex['DIVERGENCE'])     { return 'DIVERGENCE' }
    if ($pushOut -match $regex['NETWORK'])        { return 'NETWORK' }
    if ($pushOut -match $regex['AUTHENTICATION']) { return 'AUTHENTICATION' }
    return 'NOT CLASSIFIED'
}

Write-Output 'Group 2 - real git output lands in the right class'
$cases = @(
    @{ Name = 'divergence: fetch first'; Expected = 'DIVERGENCE'
       Text = " ! [rejected]        main -> main (fetch first)`nerror: failed to push some refs to 'https://github.com/example/repo.git'`nhint: Updates were rejected because the remote contains work that you do not`nhint: have locally." }
    @{ Name = 'divergence: non-fast-forward'; Expected = 'DIVERGENCE'
       Text = " ! [rejected]        main -> main (non-fast-forward)`nerror: failed to push some refs" }
    @{ Name = 'network: DNS does not resolve'; Expected = 'NETWORK'
       Text = "fatal: unable to access 'https://github.com/example/repo.git/': Could not resolve host: github.com" }
    @{ Name = 'network: connection timed out'; Expected = 'NETWORK'
       Text = 'fatal: unable to access: Failed to connect to github.com port 443: Connection timed out' }
    @{ Name = 'auth: invalid credential'; Expected = 'AUTHENTICATION'
       Text = "remote: Invalid username or password.`nfatal: Authentication failed for 'https://github.com/example/repo.git/'" }
    @{ Name = 'auth: 403 / permission denied'; Expected = 'AUTHENTICATION'
       Text = "remote: Permission to example/repo.git denied to user.`nfatal: unable to access: The requested URL returned error: 403" }
    @{ Name = 'an invalid refspec is neither network nor divergence'; Expected = 'NOT CLASSIFIED'
       Text = "error: src refspec refs/heads/does-not-exist does not match any`nerror: failed to push some refs to 'https://github.com/example/repo.git'" }
)
foreach ($c in $cases) {
    $got = Classify $c.Text
    Assert-True $c.Name ($got -eq $c.Expected) ("classified {0}, expected {1}" -f $got, $c.Expected)
}

Write-Output 'Group 3 - the error-record decoration is stripped, the git text stays'
# Windows PowerShell 5.1 wraps a native executable's stderr; this is the real shape,
# in both the English and a localised prefix the script has to recognise.
$real = @'
git : error: src refspec refs/heads/does-not-exist does not match any
At line:3 char:1
+ git -C 'C:\Path\To\repo' push origin refs/heads/does-not-exist
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (error: src refs...match any:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError

error: failed to push some refs to 'https://github.com/example/repo.git'
'@
$m = [regex]::Match($text, '(?s)function Get-GitSaid.*?\n\}')
Assert-True 'Get-GitSaid exists in the script' $m.Success
if ($m.Success) {
    . ([scriptblock]::Create($m.Value))
    $cleaned = Get-GitSaid $real
    Assert-True 'the error-record furniture is gone' ($cleaned -notmatch 'CategoryInfo|FullyQualifiedErrorId|At line:|~~~~') $cleaned
    Assert-True 'both git lines survived' (($cleaned -match 'error: src refspec') -and ($cleaned -match 'error: failed to push some refs')) $cleaned
    Assert-True 'the "git : " prefix was removed' ($cleaned -notmatch '^git\s*:')
    $localised = $real -replace 'At line:3 char:1', 'No linha:3 caractere:1'
    $cleaned2 = Get-GitSaid $localised
    Assert-True 'a localised "At line:" prefix is stripped as well' ($cleaned2 -notmatch 'No linha:') $cleaned2
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
