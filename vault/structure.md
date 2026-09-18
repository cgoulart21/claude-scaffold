# Creating the vault

## The folders

```
<vault-root>/
  AGENTS.md              from AGENTS.md.template, paths adapted
  raw/
    sources/             immutable source material - read-only
    assets/              images, PDFs, recordings
  wiki/
    sources/             one summary page per ingested source
    entities/            people, organisations, projects, tools
    concepts/            ideas, methods, patterns
    queries/             syntheses, answers, red-team reports
    notes/               the human's own notes - never edited by the agent
    meta/
      index.md           the master catalogue
      log.md             append-only operations log
```

Create `index.md` and `log.md` empty. They are the two files every operation touches, and an
operation that cannot find them will quietly skip updating them.

## Trap 1 - a cloud-synced folder

If the vault sits inside a folder that a sync client watches, that client and git will both
try to manage the same `.git` directory. The result is conflicted objects, phantom
modifications and, occasionally, a repository that will not open.

Keep the vault outside synced storage if you can. If you cannot, put the git directory
somewhere the sync client does not watch:

```bash
git init --separate-git-dir "C:\Path\To\vault-git" "C:\Path\To\synced\vault"
```

The working tree stays where the sync client expects it; the repository internals live
outside its reach. Verify it took effect - the vault folder should contain a `.git` **file**
holding a path, not a `.git` directory.

One more thing, and it is the one that bites: **if you ever had a copy of this vault in
another location, decide which one is live and write that decision down.** A dead copy that
still opens is indistinguishable from the live one, and edits made in the wrong one are
silently lost.

## Trap 2 - binaries in git

A vault accumulates PDFs, images and recordings, and git stores every version of each in
full. A few months of that makes clones slow and history heavy.

Track them with Git LFS from the start, not after it hurts:

```bash
git lfs install
git lfs track "raw/assets/**"
git add .gitattributes
```

Do this **before** the first commit that adds a binary. Migrating afterwards means
rewriting history, which is exactly the operation you do not want to perform on the only
copy of your research.

## First run

1. Create the folders above and copy `AGENTS.md.template` in as `AGENTS.md`, adapting paths.
2. `git init` (with `--separate-git-dir` if trap 1 applies), then set up LFS.
3. Commit the empty structure, so the first real page has something to diff against.
4. Open it in your editor of choice and ingest one source, end to end, to prove the loop
   works before you rely on it.

That last step matters more than it looks. A vault that has never completed one full ingest
is a folder structure with aspirations - you find out what does not work on the day you have
something worth filing.
