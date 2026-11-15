# Links the suite's addon folders from a clone of this repository into your WoW AddOns folder,
# so you can edit the code in the clone and /reload in game.
#
#   pwsh -File scripts\link-addons.ps1 -AddOns "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
#
# Uses directory junctions (no admin rights needed). Skips folders that already point here; refuses to touch a
# real folder of the same name (move or delete your old copy first).
# Not needed if you cloned the repository directly into the AddOns folder.
param(
    [Parameter(Mandatory)][string]$AddOns
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path $AddOns)) { throw "AddOns folder not found: $AddOns" }
if ((Resolve-Path $AddOns).Path -eq (Resolve-Path $repo).Path) { "The repository already is the AddOns folder; nothing to link."; return }

foreach ($a in 'RavenquillExpedition', 'RavenquillExpedition_Map', 'RavenquillExpedition_Highlights', 'RavenquillExpedition_CraftAdvisor') {
    $src = Join-Path $repo $a
    $dst = Join-Path $AddOns $a
    if (-not (Test-Path $src)) { "skip  $a (not in this clone)"; continue }
    if (Test-Path $dst) {
        $item = Get-Item $dst -Force
        if ($item.LinkType -and ($item.Target -contains $src -or $item.Target -contains (Resolve-Path $src).Path)) { "ok    $a (already linked)"; continue }
        throw "$dst already exists and is not a link to this clone. Move or delete it first."
    }
    New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
    "link  $a -> $src"
}
