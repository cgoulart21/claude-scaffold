<#
  backup-config.ps1 — biweekly: back up your authored ~/.claude artifacts to your private
  config repo (sync -> commit-if-changed -> push). Runs at the same ~14-day cadence as
  check-updates.ps1 (see the global CLAUDE.md "Tool updates" trigger). Session-driven
  (app context) so git/gh auth works. Safe to run anytime; no-op when nothing changed.
  Uses Write-Output (not Write-Host) so the run is captured/loggable.

  SETUP: create a PRIVATE git repo that mirrors your authored ~/.claude artifacts, add a
  `sync.ps1` there that copies them in, and point $repo below at it.
#>
$ErrorActionPreference = 'Continue'
$repo = '<PATH-TO-YOUR-PRIVATE-CONFIG-REPO>'   # e.g. C:\your\path\claude-setup

if (-not (Test-Path (Join-Path $repo '.git'))) {
    Write-Output "Backup: claude-setup repo nao encontrado em $repo - pulando."
    return
}

# 1. pull authored files ~/.claude -> repo
& (Join-Path $repo 'sync.ps1') | Out-Null

# 2. commit only if something actually changed
$changes = git -C $repo status --porcelain
if ([string]::IsNullOrWhiteSpace($changes)) {
    Write-Output "Backup: nada mudou desde o ultimo push."
    return
}
git -C $repo add -A
$stamp = Get-Date -Format 'yyyy-MM-dd'
git -C $repo commit -q -m "backup: sync autoral $stamp (checagem quinzenal)"

# 3. push (needs the app-context session for gh/git auth)
git -C $repo push -q origin main
if ($LASTEXITCODE -eq 0) {
    Write-Output "Backup: commitado e enviado ($stamp)."
} else {
    Write-Output "Backup: commit local OK, push FALHOU - checar rede/gh e rodar 'git -C $repo push'."
}
