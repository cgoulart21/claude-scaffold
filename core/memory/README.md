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

**What a silo is, exactly.** The host keeps one directory per working directory under
`<AGENT-HOME>\projects\<cwd>\`. That directory holds the session transcripts (`*.jsonl`)
*and* a `memory\` subfolder. The silo is the **subfolder**. The script converts
`<cwd>\memory` and never touches `<cwd>` itself.

Run the script without `-Apply` first. It writes nothing and reports one line per project,
with the **full path** of the candidate:

```powershell
.\Set-MemoryJunctions.ps1 -MemoryRoot <MEMORY-STORE> -SiloRoot <AGENT-HOME>\projects
```

```
  real-folder         <AGENT-HOME>\projects\<cwd-1>\memory
  ok                  <AGENT-HOME>\projects\<cwd-2>\memory
  missing             <AGENT-HOME>\projects\<cwd-3>\memory

3 project(s): 1 correct, 2 divergent, 0 refused
Re-run with -Apply to convert the divergent ones. Files are carried into the store first.
```

**Read the paths before you read the verdicts.** Every line must end in `\memory`. If the
script ever lists the project directories themselves, stop: it is looking at the wrong
level, and `-Apply` would carry your transcripts into the store and remove the directories.
That is exactly what a version before 2026-09-20 did, and a second machine caught it in
dry run because the paths were on screen. The fixture in `tools/` now models the host's
layout - a transcript beside `memory\` that must stay where it is - but the fixture proves
the script does what the fixture describes; the paths on your screen prove it does what
your machine needs.

Exit `0` means every silo is already a junction into the store; `1` means at least one is
not, or one was **refused**; `2` means it could not run at all.

A candidate is refused, and never converted, when it holds `*.jsonl` (then it is a project
directory, whatever it is called) or when it holds a reparse point (removing a directory
that contains a junction can remove the junction's target). Refused lines say why; resolve
them by hand.

With `-Apply`, a real folder is **copied into the store before it is removed**, and a file
already present in the store is never overwritten - the store's copy may be the newer one.
That ordering is the whole safety argument: converting a folder into a junction destroys
its contents, and some of those contents may exist nowhere else.

## Renaming a memory breaks the links that point at it

A rename's blast radius is its **incoming** links, and whoever wrote them is not told the
target changed. One practice renamed a memory file and the `[[old-name]]` inside another
memory dangled for a day; nothing pointed at it - it surfaced because a different session
mentioned the rename in passing.

`automation/verification/Assert-MemoryLinks.ps1 -MemoryRoot <MEMORY-STORE>` catches the new
dangling link. It does not demand that every link resolve - the conventions above allow a link
to a memory not yet written - so unresolved targets you have decided on go in `-KnownDangling`,
each with its reason next to it in the caller. An exception that resolves again, or that
nobody cites any more, fails the run: the list has to stay true or it lies quietly.

## A junction inside a repository is invisible to git

Worth knowing before you put a reparse point anywhere under version control, because
nothing warns you.

Where `core.symlinks` is `false` - the usual case on Windows - git **follows** a junction
and records the target's bytes as ordinary blobs (`100644`), never as a link (`120000`).
The repository keeps no record that a link was ever there. `git status` stays clean, but
only because the live target still matches what was committed: edit or delete the target
and the "versioned" file changes silently. One archive built this way turned out to be
twelve directories of links into a live skill root; removing one skill from that live root
made twelve archived files show up as deleted. **An archive made of links is not an
archive** - it evaporates along with the thing it was meant to preserve.

Two consequences for this layout. The junctions belong in the agent home, which is not a
repository, and the memory store belongs in the repository, which holds no junctions -
keep that direction and the trap never fires. If you do find a reparse point inside a
repository, remove the link itself with `[IO.Directory]::Delete($path, $false)`, which
deletes only the reparse point and **fails** on a real non-empty folder; that failure is
the safety net. Never `rm -rf`, which would follow the link into the live target. Restoring
the real content with `git checkout` fails while the link is still there, so the order is
forced: remove the link, then check out, then compare hashes against a manifest captured
beforehand.
