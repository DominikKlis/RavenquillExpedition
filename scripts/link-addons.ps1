param(
    [Parameter(Mandatory)][string]$AddOns,
    [switch]$Dev
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path $AddOns)) { throw "AddOns folder not found: $AddOns" }
if ((Resolve-Path $AddOns).Path -eq (Resolve-Path $repo).Path) { "The repository already is the AddOns folder; nothing to link."; return }

$folders = git -C $repo ls-files '*.toc' | ForEach-Object { if ($_ -match '^(RavenquillExpedition[^/]*)/\1\.toc$') { $Matches[1] } }
if (-not $Dev) { $folders = $folders | Where-Object { $_ -ne 'RavenquillExpedition_Dev' } }
foreach ($a in $folders) {
    $src = Join-Path $repo $a
    $dst = Join-Path $AddOns $a
    if (Test-Path $dst) {
        $item = Get-Item $dst -Force
        if ($item.LinkType -and ($item.Target -contains $src -or $item.Target -contains (Resolve-Path $src).Path)) { "ok    $a (already linked)"; continue }
        throw "$dst already exists and is not a link to this clone. Move or delete it first."
    }
    New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
    "link  $a -> $src"
}
