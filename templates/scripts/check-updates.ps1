<#
  check-updates.ps1
  --------------------------------------------------------------------------
  Varredura READ-ONLY de atualizacoes de tudo que temos instalado.
  NAO aplica NADA. So le versoes instaladas vs disponiveis e escreve um
  relatorio em ~/.claude/maintenance/updates-<data>.md (+ updates-latest.md).

  Nao usa `claude -p` (inferencia), so CLIs de gerenciamento -> sem problema de auth.
  Se o app for MSIX/Store-packaged, rode DENTRO da sessao do Claude (o AppData\Roaming
  virtualizado esconde os npm globals de um Task Scheduler externo; `npm outdated -g` daria
  ENOENT fora do sandbox). Trigger recomendado: session-driven via CLAUDE.md global (ver
  SCAFFOLD Phase 5). Aplicar updates continua deliberado (ver secao final do relatorio).
  --------------------------------------------------------------------------
#>
$ErrorActionPreference = 'Continue'

$claudeHome = Join-Path $env:USERPROFILE '.claude'
$maint      = Join-Path $claudeHome 'maintenance'
New-Item -ItemType Directory -Force -Path $maint | Out-Null
$today  = Get-Date -Format 'yyyy-MM-dd'
$report = Join-Path $maint "updates-$today.md"
$latest = Join-Path $maint 'updates-latest.md'

$script:lines = @()
$script:updCount = 0
function Add-Line($m){ $script:lines += $m }

Add-Line "# Relatorio de atualizacoes - $today"
Add-Line ""
Add-Line "Varredura read-only. NADA foi aplicado. Aplique deliberadamente (ver fim)."
Add-Line ""

# --- 1. Plugins do Claude Code -------------------------------------------------
Add-Line "## Plugins do Claude Code"
if (Get-Command claude -ErrorAction SilentlyContinue) {
    claude plugin marketplace update | Out-Null   # git pull dos marketplaces (nao toca instalados)
    try {
        $inst = Get-Content (Join-Path $claudeHome 'plugins\installed_plugins.json') -Raw | ConvertFrom-Json
        $avail = @{}
        Get-ChildItem (Join-Path $claudeHome 'plugins\marketplaces') -Directory | ForEach-Object {
            $mj = Join-Path $_.FullName '.claude-plugin\marketplace.json'
            if (Test-Path $mj) {
                try {
                    $d = Get-Content $mj -Raw | ConvertFrom-Json
                    $mpname = $d.name; if (-not $mpname) { $mpname = $_.Name }
                    foreach ($p in $d.plugins) { $avail["$mpname/$($p.name)"] = $p.version }
                } catch {}
            }
        }
        foreach ($prop in $inst.plugins.PSObject.Properties) {
            $key = $prop.Name
            $iv  = $prop.Value[0].version
            $parts = $key.Split('@',2); $name = $parts[0]; $mp = $parts[1]
            $av = $avail["$mp/$name"]
            if (-not $av)          { Add-Line "- $key : $iv  (disponivel: nao comparavel automaticamente - checar manual)" }
            elseif ($av -ne $iv)   { Add-Line "- $key : $iv -> **$av**  [UPDATE]"; $script:updCount++ }
            else                   { Add-Line "- $key : $iv  (atualizado)" }
        }
    } catch { Add-Line "- ERRO ao comparar plugins: $($_.Exception.Message)" }
} else { Add-Line "- 'claude' nao esta no PATH deste contexto - pulado." }
Add-Line ""

# --- 2. CLIs globais (npm) -----------------------------------------------------
Add-Line "## CLIs globais (npm)"
if (Get-Command npm -ErrorAction SilentlyContinue) {
    # 1 retry: npm as vezes retorna {"error":...} num blip transitorio de registry
    $npmRaw = ''
    foreach ($try in 1..2) {
        $npmRaw = (npm outdated -g --json 2>$null | Out-String).Trim()
        if ($npmRaw -notmatch '"error"') { break }
        Start-Sleep -Seconds 3
    }
    if (-not $npmRaw -or $npmRaw -eq '{}') {
        Add-Line "- (todos atualizados)"
    } else {
        try {
            $npm = $npmRaw | ConvertFrom-Json
            if ($npm.PSObject.Properties.Name -contains 'error') {
                Add-Line "- npm outdated retornou erro (transitorio?) - rode manualmente: ``npm outdated -g``"
            } else {
                $any = $false
                foreach ($p in $npm.PSObject.Properties) {
                    $lat = $p.Value.latest
                    if ($lat) {   # so conta entradas validas (com .latest)
                        Add-Line "- $($p.Name) : $($p.Value.current) -> **$lat**  [UPDATE]"; $script:updCount++; $any = $true
                    }
                }
                if (-not $any) { Add-Line "- (todos atualizados)" }
            }
        } catch { Add-Line "- ERRO ao parsear npm outdated: $($_.Exception.Message)" }
    }
} else { Add-Line "- 'npm' nao esta no PATH deste contexto - pulado." }
Add-Line ""

# --- 3. Checar manualmente (nao automatizado) ---------------------------------
Add-Line "## Checar manualmente"
Add-Line "- Skills (mattpocock / find-skills / task-observer): ``npx skills update -g``"
Add-Line "- Impeccable (skill global): ``npx impeccable update`` dentro de um projeto front-end"
Add-Line ""

# --- 4. NAO auto-atualizar (pinado/acoplado) ----------------------------------
Add-Line "## NAO auto-atualizar (pinado/acoplado - so deliberado)"
Add-Line "# Liste aqui SEUS itens pinados/acoplados (edite conforme seu setup). Exemplos:"
Add-Line "- <plugin com runtime Python>: rode o script per-tool que ressincroniza o venv"
Add-Line "- <toolchain pinada>: PINADA em <versao> (update quebra os builds)"
Add-Line ""
Add-Line "---"
Add-Line "Total com update disponivel: $script:updCount"
Add-Line ""
Add-Line "Lembre: aplicar plugin do Claude tambem exige RESTART do app."

$body = ($script:lines -join "`r`n")
Set-Content -Path $report -Value $body -Encoding UTF8
Set-Content -Path $latest -Value $body -Encoding UTF8

Write-Output "Relatorio: $report"
Write-Output "Updates disponiveis: $script:updCount"
