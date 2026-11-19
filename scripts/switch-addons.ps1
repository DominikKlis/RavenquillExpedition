param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('dev', 'curseforge')][string]$Use,
    [string]$AddOns
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

if (-not $AddOns) {
    $game = if ($env:WOW_DIR) { $env:WOW_DIR } else { Join-Path ${env:ProgramFiles(x86)} 'World of Warcraft\_forever_' }
    $AddOns = Join-Path $game 'Interface\AddOns'
}
if (-not (Test-Path $AddOns)) { throw "AddOns folder not found: $AddOns (pass -AddOns or set WOW_DIR)" }
$AddOns = (Resolve-Path $AddOns).Path
if ($AddOns -eq (Resolve-Path $repo).Path) { throw 'This clone is the AddOns folder itself; move it elsewhere first.' }

$gameDir = Split-Path (Split-Path $AddOns -Parent) -Parent
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -like 'Wow*' -and $_.Path -and $_.Path.StartsWith($gameDir, [StringComparison]::OrdinalIgnoreCase)
}
if ($running) { throw 'Close the game first: it only loads the other copy after a full restart.' }

$parked = Join-Path (Split-Path $AddOns -Parent) 'RavenquillExpedition-CurseForge'
$folders = git -C $repo ls-files '*.toc' | ForEach-Object { if ($_ -match '^(RavenquillExpedition[^/]*)/\1\.toc$') { $Matches[1] } }

function Test-Link([string]$Path) {
    (Test-Path $Path) -and [bool](Get-Item $Path -Force).LinkType
}

function Use-Dev {
    foreach ($a in $folders) {
        $dst = Join-Path $AddOns $a
        if (-not (Test-Path $dst) -or (Test-Link $dst)) { continue }
        $park = Join-Path $parked $a
        if (Test-Path $park) { throw "$park already exists; move it away first." }
        New-Item -ItemType Directory -Force $parked | Out-Null
        Move-Item $dst $park
        "park    $a -> $park"
    }
    & (Join-Path $PSScriptRoot 'link-addons.ps1') -AddOns $AddOns -Dev
    'The game now loads this clone. Keep the CurseForge app from updating the suite while it is linked.'
}

function Use-CurseForge {
    foreach ($a in $folders) {
        $dst = Join-Path $AddOns $a
        if (Test-Link $dst) {
            [IO.Directory]::Delete($dst, $false)
            "unlink  $a"
        } elseif (Test-Path $dst) {
            "ok      $a (already the CurseForge copy)"
            continue
        }
        $park = Join-Path $parked $a
        if (Test-Path $park) {
            Move-Item $park $dst
            "restore $a"
        }
    }
    if ((Test-Path $parked) -and -not (Get-ChildItem $parked -Force)) { Remove-Item $parked }
    'The game now loads the CurseForge copy.'
}

if ($Use -eq 'dev') { Use-Dev } else { Use-CurseForge }
