# Memory - one physical folder, many names

Memory here means **tool gotchas and project context**: the things you would get wrong
again without a note. Method and verification discipline do not live here - they live in
the cross-cutting lessons file, `LESSONS.md`. Keeping the two apart is what keeps either
one readable.

## The model

Most agent setups give each working directory its own memory store. That silo is the
failure: a fact written while working on one project stays invisible to every session in
every other project, and you pay to learn it twice.

The fix is one **physical** folder, with each per-directory silo replaced by a junction
into it. Writing memory from any session lands in the same place, and every session reads
everything.

```
<MEMORY-STORE>/                     the only real folder
  MEMORY.md                         the index - authored, not generated
  some-tool-gotcha.md
  another-gotcha.md

<AGENT-HOME>/projects/<dir-a>/memory   junction  ->  <MEMORY-STORE>
<AGENT-HOME>/projects/<dir-b>/memory   junction  ->  <MEMORY-STORE>
```

Put `<MEMORY-STORE>` inside a git repository you control. That is what turns "notes the
agent keeps" into something you can review, revert and carry to a new machine.

## Detecting a junction - measure, do not eyeball

**A folder that looks empty is not evidence, and a folder with files in it is not evidence
either.** A real folder fed by an occasional copy looks exactly like a junction from the
outside, right up until you notice its contents are hours or days stale.

Measure the reparse-point attribute:

```powershell
$item = Get-Item -LiteralPath $path -Force
($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
```

The command-line equivalent is `fsutil reparsepoint query <path>`: reparse tag
`0xa0000003` means a mount point, and an error ("not a reparse point") means it is a real
folder. The two agree; the attribute check is preferred because it needs no external tool
and no elevation. `Set-MemoryJunctions.ps1` in this folder uses both - the attribute to
classify, and `fsutil` to read a junction's target, which Windows PowerShell 5.1 does not
expose on its own.

> When parsing `fsutil` output, anchor on the `\??\` prefix, never on the label before it.
> Those labels are printed in the system language, so label-based parsing works on the
> machine you wrote it on and fails on everyone else's.

## The index is authored, not mirrored

`MEMORY.md` is written by hand, one line per memory, ordered and grouped the way you
actually think about your tools. It is **not** generated from the folder listing.

The reason is practical: a generated index is a second copy of the directory, and it adds
nothing you could not get from `ls`. An authored index carries the judgement - which
gotchas matter, which belong together, which one you would want surfaced first - and that
judgement is the only part worth reading at the start of a session.

A sync script may warn you that a file on disk has no line in the index. It should never
write that line for you.

## Files here

| File | What it is |
|---|---|
| `memory-file.template.md` | The shape of one memory: frontmatter plus body |
| `MEMORY.md.template` | An empty index with the conventions written down |
| `Set-MemoryJunctions.ps1` | Classifies each silo and, with `-Apply`, converts it |

## Converting an existing silo

Run the script without `-Apply` first. It writes nothing and reports one line per silo:

```powershell
.\Set-MemoryJunctions.ps1 -MemoryRoot <MEMORY-STORE> -SiloRoot <AGENT-HOME>\projects
```

Exit `0` means every silo is already a junction into the store; `1` means at least one is
not; `2` means it could not run at all.

With `-Apply`, a real folder is **copied into the store before it is removed**, and a file
already present in the store is never overwritten - the store's copy may be the newer one.
That ordering is the whole safety argument: converting a folder into a junction destroys
its contents, and some of those contents may exist nowhere else.
