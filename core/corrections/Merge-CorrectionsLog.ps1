<#
  Merge-CorrectionsLog.ps1

  Union of the corrections log between the live copy and the repository copy. The log
  is the counter the second-occurrence rule depends on; losing a line silently costs
  the whole discipline.

  WHY UNION AND NOT COPY. Two machines append to this file. A copy-over from one
  machine's live file erases from the repository the lines the OTHER machine added.

  WHY BY ENTRY AND NOT BY LINE. A union that compared literal lines treated
  `- <entry>` and `<entry>` as different strings. When one machine wrote three entries
  without the bullet, the union kept both variants of each: the fix for copy-over had a
  duplication mode of its own, found by a weekly routine with 3 duplicates already in
  the log. The identity key is now the line without its bullet and with whitespace
  collapsed; the bullet is restored on write.

  CONTRACTS THE SUITE FIXES:
   1. no entry from either side disappears;
   2. an entry differing only by bullet or whitespace is ONE entry;
   3. an entry edited in place on one machine (a promotion marker appended) collapses
      onto the LONGER wording, which is the one carrying the marker - but only when one
      wording is a strict PREFIX of the other, above a minimum length. A first version
      compared the first 60 characters and kept the longer: that DELETED distinct
      entries - two observations about the same tool on the same day share 60
      characters easily and diverge later. Strict prefix has no such false positive;
   4. the repository's order is preserved and what only the live copy has goes last;
   5. header prose that only the live copy has is NOT erased: the live file is not
      rewritten, and the caller is told (verification must not damage the user's state);
   6. idempotent: the result ends with exactly one line break, so re-feeding the output
      does not grow the file by a blank line per pass and turn every sync into churn.

  Returns an object: MergedText, Added, Collapsed (the discarded TEXTS, not a count -
  whoever discards text from a user's log must be able to show what was discarded),
  LiveOnlyProse, WriteLive.
#>
param(
    # AllowEmptyString is mandatory here: in Windows PowerShell 5.1 a [string[]] marked
    # Mandatory rejects the WHOLE array when any element is '' - and the log has blank
    # lines between header and entries.
    [AllowEmptyString()] [AllowEmptyCollection()] [string[]] $RepoLines = @(),
    [AllowEmptyString()] [AllowEmptyCollection()] [string[]] $LiveLines = @(),
    [string] $NewLine = [Environment]::NewLine,
    # Floor for accepting a prefix relation as "same entry". Below it both stay: keeping
    # two is recoverable, deleting one is not.
    [int] $MinPrefixLength = 40
)

# Identity key of an entry; $null when the line is not an entry.
function Get-LogEntryKey([string] $Line) {
    $s = $Line.Trim()
    if (-not ($s -match '^(- )?20\d\d-\d\d-\d\d\s')) { return $null }
    if ($s.StartsWith('- ')) { $s = $s.Substring(2) }
    return [regex]::Replace($s, '\s+', ' ')
}

$merged    = New-Object -TypeName Collections.ArrayList
$byKey     = @{}
$byDate    = @{}
$added     = 0
$collapsed = New-Object -TypeName Collections.ArrayList

# Header prose is not part of the union: it is a bootstrap template, written once, and
# its order matters - the repository dictates the form. But prose only the live copy has
# would be LOST when the live file is rewritten, so it is detected, reported, and the
# live file is left alone.
$repoProse = @{}
foreach ($l in $RepoLines) { if ($null -eq (Get-LogEntryKey $l)) { $repoProse[$l.Trim()] = $true } }
$liveOnlyProse = @($LiveLines | Where-Object {
    $null -eq (Get-LogEntryKey $_) -and $_.Trim() -ne '' -and -not $repoProse.ContainsKey($_.Trim())
})

foreach ($side in @(@{ L = $RepoLines; New = $false }, @{ L = $LiveLines; New = $true })) {
    foreach ($line in $side.L) {
        $key = Get-LogEntryKey $line
        if ($null -eq $key) {
            if (-not $side.New) { [void] $merged.Add($line) }
            continue
        }
        $canon = '- ' + $key
        if ($byKey.ContainsKey($key)) { continue }

        # Same entry in two wordings = one is a strict prefix of the other, limited to the
        # SAME DAY (an in-place edit does not change the date) and above $MinPrefixLength.
        $date  = $key.Substring(0, 10)
        $cands = if ($byDate.ContainsKey($date)) { $byDate[$date] } else { @() }
        $shorterExisting = $null
        $longerExisting  = $null
        foreach ($c in $cands) {
            if ($c.Length -lt $key.Length -and $c.Length -ge $MinPrefixLength -and $key.StartsWith($c, [StringComparison]::Ordinal)) { $shorterExisting = $c; break }
            if ($key.Length -lt $c.Length -and $key.Length -ge $MinPrefixLength -and $c.StartsWith($key, [StringComparison]::Ordinal)) { $longerExisting = $c; break }
        }
        if ($null -ne $shorterExisting) {
            $idx = $byKey[$shorterExisting]
            [void] $collapsed.Add($shorterExisting)
            $merged[$idx] = $canon
            $byKey.Remove($shorterExisting)
            $byKey[$key] = $idx
            $byDate[$date] = @($byDate[$date] | Where-Object { $_ -ne $shorterExisting }) + $key
            continue
        }
        if ($null -ne $longerExisting) {
            [void] $collapsed.Add($key)
            continue
        }

        $byKey[$key] = $merged.Count
        if ($byDate.ContainsKey($date)) { $byDate[$date] = @($byDate[$date]) + $key } else { $byDate[$date] = @($key) }
        [void] $merged.Add($canon)
        if ($side.New) { $added++ }
    }
}

while ($merged.Count -gt 0 -and [string]::IsNullOrWhiteSpace($merged[$merged.Count - 1])) {
    $merged.RemoveAt($merged.Count - 1)
}

[pscustomobject] @{
    MergedText    = ([string]::Join($NewLine, $merged.ToArray()) + $NewLine)
    Added         = $added
    Collapsed     = @($collapsed.ToArray())
    LiveOnlyProse = $liveOnlyProse
    WriteLive     = ($liveOnlyProse.Count -eq 0)
}
