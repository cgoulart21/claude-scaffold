# Manifest - what to install, and from where

> Snapshot as of 2026-09-17. Versions move; re-check before running anything here.

Nothing third-party is vendored in this repository. Everything below is installed **from its
own source**, so upstream fixes reach you and nobody has to maintain a fork.

## 1. Marketplaces

```bash
claude plugin marketplace add obra/superpowers-marketplace
```

Add others as you need them. A marketplace that ships its content under a subdirectory needs
a sparse path, and **that path is a version-coupled detail**: when one upstream moved its
content from one folder to another, every update silently downloaded an empty cache until
someone compared against the real upstream tree. If updates start doing nothing, check the
sparse path before you check anything else.

## 2. Plugins

```bash
claude plugin install superpowers@superpowers-marketplace --scope user
```

Install the *core* of a large plugin and skip its optional companions unless you have
decided you want them. Memory plugins in particular overlap with `core/memory/` and you will
end up with two systems disagreeing about where a fact lives.

## 3. Third-party skills

```bash
npx skills add <owner>/<repo> --skill <name> --global --copy -y
```

**Name each skill explicitly.** An allowlist is the difference between a reproducible set and
a set that depends on when you last ran the command - see the reasoning in `README.md`.

Repositories worth knowing about, as of this snapshot:

| Repository | Note |
|---|---|
| `mattpocock/skills` | A large collection; pick by name. Upstream renames skills occasionally, which leaves the old name orphaned on disk - nothing recreates it and no allowlist removes it |
| `vercel-labs/skills` | `find-skills`, for discovering what else exists |
| `kepano/obsidian-skills` | `obsidian-markdown` and `defuddle`; the latter also needs its CLI |

A harmless warning about global installation may appear; the skill file still copies.

## 4. CLIs

```bash
npm install -g <package>
```

Install only what a skill you actually use depends on. Anything needing its own credentials
is yours to set up - this repository never ships a key, and no scaffold should.

## 5. The skills in this repository

Copy them into your global skills directory:

```
stack/skills/design-smells/
stack/skills/source-grounded/
stack/skills/diagnose/
stack/skills/scientific-project-report/
```

`diagnose` is a customisation of an upstream skill. If you also install the upstream
collection, deploy this copy **over** it, or you will get whichever the installer wrote
last. `scientific-project-report` carries its own CC BY 4.0 licence file; keep the file with
the folder.

## 6. Gitleaks - the secret scanner

`automation/verification/Invoke-Gitleaks.ps1` wraps a binary this repository does not ship.
The wrapper is method and lives in `automation/`; the version and the URL are inventory and
live here, because they age.

**Version 8.30.1, as of 2026-09-17.** Check the releases page for a newer one before using
this.

```powershell
$version = '8.30.1'
$url = "https://github.com/gitleaks/gitleaks/releases/download/v$version/gitleaks_${version}_windows_x64.zip"
$dest = Join-Path $env:USERPROFILE '.local\bin'
```

Download the archive **and the release's own checksums file**, verify the SHA-256 of what
you downloaded against it, then extract `gitleaks.exe` into `$dest`. Do not skip the
checksum: a secret scanner is a security tool, and an unverified security tool is a worse
bargain than no tool, because you will trust its green result.

On macOS and Linux, use the platform archive from the same release, or a package manager if
it carries the version you want.

**Pin the version in the calling hook, and refuse a different one.** A pre-commit hook that
accepts whatever binary happens to be on the path has not validated the behaviour it
reports - a scanner you did not pin is a scanner whose findings you did not define. The
shape that works:

```sh
if [ "$("$gitleaks_bin" version 2>/dev/null)" != "8.30.1" ]; then
  echo "Gitleaks 8.30.1 is required; refusing to run a different version." >&2
  exit 1
fi
```

Refusing is the point. Falling back to "scan anyway with whatever is there" converts a
version mismatch into a silent change in what counts as a finding.

## 7. Pinned on purpose

Keep a list here, with the reason and the upstream issue link for each pin. This section is
empty on purpose: your pins are yours, and an inherited pin with no reason attached is one
that gets removed the first time somebody tidies up.

## 8. Heavy or semi-manual

Language runtimes, hardware toolchains, MCP servers and anything with its own installer are
listed by name in `domain-tools.md` and set up by hand. They tend to carry coupled versions
and their own credentials, which makes them a poor fit for a scaffold's install script.
