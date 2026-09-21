<#
  Assert-MemoryIndex.ps1

  Gate: every memory in the store has exactly one line in MEMORY.md, and the hook on that
  line is the memory's `description` - verbatim, within the cap, and a plain YAML scalar.

  WHY IT EXISTS. The index and the frontmatter both carry a text whose only job is to
  answer "is this the memory I need?" before the file is opened. Two texts with one job
  drift apart. In the practice this gate came from, the index had grown a second hook per
  memory, written apart from the description, longer (the median above the cap, the
  longest near four times it) and different from the description in all but one file.
  The index had become a second body. Nothing said so, because nothing compared the two
  surfaces.

  THE CONTRACT. One text: the `description:` in the frontmatter. The index repeats it,
  character for character, after the link:
      - [Title](file-name.md) <sep> <description>
  with <sep> one of hyphen, em dash, en dash. The description exists, is one line, and is
  at most -MaxLength characters (200). One source, two surfaces, one gate between them.

  WHY A PLAIN YAML SCALAR. The host parses the frontmatter as YAML. A description with
  ": " becomes a mapping and the parse fails; wrapped in quotes, the text the parser
  returns is not the text in the file, so an index that repeats the file verbatim would
  drift from what the host sees. Hence: no wrapping quotes, no ": ", no " #", no trailing
  colon, no YAML-special first character. A colon WITHOUT a space after it (a time, a
  URL) is free.

  WHAT IT DOES NOT DO. It does not judge the wording of the hook, nor which section the
  line sits in: grouping is curation and stays authored. It does not read the body. It
  never writes the index - MEMORY.md is authored, not mirrored.

  PARSER. The title may contain brackets ("Guard [tag] fires"): it is matched lazily up
  to the first "](" followed by a .md file name. A parser that stopped at the first "]"
  would report the memory as missing from the index - which is what fooled a measurement
  once. And a malformed file name in a line is a formatted finding, never an exception:
  Test-Path throws on "|" under Stop, and an exception exits 1 - the same exit as a
  finding, with the diagnosis lying to whoever reads only the code.

  EXIT CONTRACT (three states):
    0  every hook is its memory's description, every description fits the cap and is a
       plain scalar
    1  a finding: memory not in the index, line without a file, duplicate line, line
       without a separator, invalid file name, no one-line description, description too
       long or not a plain scalar, hook differs
    2  could NOT verify: -MemoryRoot missing or absent, no MEMORY.md, no memory file to
       sweep (an empty sweep is not a clean sweep), or a break such as an unreadable
       file - no break path reaches 1

  PARAMETERS
    -MemoryRoot   The memory store. Required: this gate cannot guess where yours is.
    -MaxLength    Cap on the description, in characters. Default 200.
    -Quiet        Print findings and the count only; no summary, no OK line.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $MemoryRoot,
    [int]    $MaxLength = 200,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'

function Say([string] $m) { if (-not $Quiet) { Write-Output $m } }
function Fail([string] $m) { Write-Output ('FAIL  ' + $m) }

try {
    if ([string]::IsNullOrEmpty($MemoryRoot)) {
        Write-Output 'COULD NOT VERIFY: -MemoryRoot is required (this gate does not know where your store is).'
        exit 2
    }
    if (-not (Test-Path -LiteralPath $MemoryRoot -PathType Container)) {
        Write-Output "COULD NOT VERIFY: memory root does not exist: $MemoryRoot"
        exit 2
    }
    $indexPath = Join-Path $MemoryRoot 'MEMORY.md'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        Write-Output "COULD NOT VERIFY: no MEMORY.md in $MemoryRoot"
        exit 2
    }
    $memories = @(Get-ChildItem -LiteralPath $MemoryRoot -File -Filter '*.md' |
        Where-Object { $_.Name -ne 'MEMORY.md' } | Sort-Object Name)
    if ($memories.Count -eq 0) {
        Write-Output "COULD NOT VERIFY: no memory file in $MemoryRoot - an empty sweep is not a clean sweep"
        exit 2
    }

    # ReadAllText honours a BOM and assumes UTF-8; Get-Content on 5.1 would read a BOM-less
    # file through the legacy code page.
    $indexText = [IO.File]::ReadAllText($indexPath)
    $dashes = @('-', [string][char]0x2014, [string][char]0x2013)
    $linePattern = '^- \[(?<title>.*?)\]\((?<file>[^()\s]+\.md)\)\s*(?<rest>.*)$'

    $entries     = @{}
    $duplicates  = @()
    $noSeparator = @()
    foreach ($raw in ($indexText -split "`r?`n")) {
        $m = [regex]::Match($raw, $linePattern)
        if (-not $m.Success) { continue }
        $file = $m.Groups['file'].Value
        $rest = $m.Groups['rest'].Value.Trim()
        $separated = $false
        foreach ($d in $dashes) {
            if ($rest.StartsWith($d)) { $rest = $rest.Substring($d.Length).Trim(); $separated = $true; break }
        }
        if (-not $separated) { $noSeparator += $file }
        if ($entries.ContainsKey($file)) { $duplicates += $file; continue }
        $entries[$file] = $rest
    }

    $findings = 0
    foreach ($file in $duplicates)  { Fail ("duplicate index line for {0}" -f $file); $findings++ }
    foreach ($file in $noSeparator) { Fail ("no separator between link and hook: {0}" -f $file); $findings++ }
    # A malformed name is a FINDING, never an exception (see PARSER above). Checked before any
    # Test-Path, and dropped from the dictionary so nothing downstream touches it.
    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    foreach ($file in @($entries.Keys | Sort-Object)) {
        if ($file.IndexOfAny($invalidChars) -ge 0) {
            Fail ("invalid file name in index line: {0}" -f $file); $findings++
            $entries.Remove($file)
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path $MemoryRoot $file) -PathType Leaf)) {
            Fail ("index line without a file: {0} does not exist in the store" -f $file); $findings++
        }
    }

    # The optional leading character is a byte order mark, built from its code point so this
    # file stays ASCII.
    $frontmatterPattern = '^' + [char]0xFEFF + '?---\r?\n(?<body>.*?)\r?\n---'
    $descPattern        = '^description:\s*(?<value>.*)$'
    foreach ($mem in $memories) {
        $name = $mem.Name
        if (-not $entries.ContainsKey($name)) {
            Fail ("not in the index: {0} has no line in MEMORY.md" -f $name); $findings++; continue
        }
        $text = [IO.File]::ReadAllText($mem.FullName)
        $fm = [regex]::Match($text, $frontmatterPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $desc = $null
        if ($fm.Success) {
            foreach ($l in ($fm.Groups['body'].Value -split "`r?`n")) {
                $dm = [regex]::Match($l, $descPattern)
                if ($dm.Success) { $desc = $dm.Groups['value'].Value.Trim(); break }
            }
        }
        # An empty value, or a folded or literal block ('>' / '|'), is not a one-line hook.
        if ([string]::IsNullOrEmpty($desc) -or $desc.StartsWith('>') -or $desc.StartsWith('|')) {
            Fail ("no one-line description: {0}" -f $name); $findings++; continue
        }
        $yamlProblem = $null
        if ($desc.StartsWith('"') -or $desc.StartsWith("'")) { $yamlProblem = 'wrapped in quotes' }
        elseif ($desc.Contains(': ')) { $yamlProblem = 'contains a colon followed by a space' }
        elseif ($desc.EndsWith(':')) { $yamlProblem = 'ends with a colon' }
        elseif ($desc.Contains(' #')) { $yamlProblem = 'contains a hash preceded by a space' }
        elseif ($desc.StartsWith('#')) { $yamlProblem = 'starts with a hash (would become a comment)' }
        elseif ('[]{}&*!|>%@`,?-'.IndexOf($desc[0]) -ge 0) { $yamlProblem = 'starts with a YAML-special character' }
        if ($null -ne $yamlProblem) {
            Fail ("description is not a plain YAML scalar ({0}): {1}" -f $yamlProblem, $name); $findings++
        }
        if ($desc.Length -gt $MaxLength) {
            Fail ("description too long: {0} has {1} characters, cap {2}" -f $name, $desc.Length, $MaxLength); $findings++
        }
        if (-not ($entries[$name] -ceq $desc)) {
            Fail ("hook differs from description: {0}" -f $name); $findings++
        }
    }

    Say ("memory: {0}" -f $MemoryRoot)
    Say ("  {0} memory file(s) | {1} index line(s) | cap {2} characters" -f $memories.Count, $entries.Count, $MaxLength)
    if ($findings -gt 0) {
        Write-Output ("{0} memory index problem(s)." -f $findings)
        exit 1
    }
    Say 'OK  every index hook is the description of its memory, every description fits the cap and is a plain YAML scalar.'
    exit 0
}
catch {
    # A break (an unreadable file, a disk or permission error) must never exit 1: 1 means
    # "finding", and whoever reads only the exit code cannot tell the two apart.
    Write-Output "COULD NOT VERIFY: $($_.Exception.Message)"
    exit 2
}
