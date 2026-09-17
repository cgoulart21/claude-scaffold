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

## 6. Pinned on purpose

Keep a list here, with the reason and the upstream issue link for each pin. This section is
empty on purpose: your pins are yours, and an inherited pin with no reason attached is one
that gets removed the first time somebody tidies up.

## 7. Heavy or semi-manual

Language runtimes, hardware toolchains, MCP servers and anything with its own installer are
listed by name in `domain-tools.md` and set up by hand. They tend to carry coupled versions
and their own credentials, which makes them a poor fit for a scaffold's install script.
