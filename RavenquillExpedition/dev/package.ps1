# Builds the Ravenquill Expedition release zip for CurseForge.
#
#   pwsh -File dev\package.ps1                      # core + Map + Highlights (default)
#   pwsh -File dev\package.ps1 -IncludeCraftAdvisor # also CraftAdvisor (blocked: CraftersJournal data, see its NOTICE.txt)
#   pwsh -File dev\package.ps1 -Version 0.2.1       # override the zip's version (default: core .toc version)
#
# Output: dev\release\RavenquillExpedition-<version>.zip, with each addon as a top-level folder.
# Excluded everywhere: dev\ folders, PLAN/HANDOFF notes, git and editor files.
param(
    [string]$Version,
    [switch]$IncludeCraftAdvisor
)
$ErrorActionPreference = 'Stop'

$coreDir   = Split-Path $PSScriptRoot -Parent          # ...\AddOns\RavenquillExpedition
$addonsDir = Split-Path $coreDir -Parent               # ...\AddOns
$outDir    = Join-Path $PSScriptRoot 'release'

$addons = @('RavenquillExpedition', 'RavenquillExpedition_Map', 'RavenquillExpedition_Highlights')
if ($IncludeCraftAdvisor) { $addons += 'RavenquillExpedition_CraftAdvisor' }

if (-not $Version) {
    $m = Select-String -Path (Join-Path $coreDir 'RavenquillExpedition.toc') -Pattern '^## Version:\s*(\S+)'
    $Version = $m.Matches[0].Groups[1].Value
}

# Paths (relative to an addon folder) that never ship.
$excludeDirs  = @('dev', '.git', '.github', '.vscode', '.idea', '.claude')
$excludeFiles = @('HANDOFF.md', 'PLAN.md', 'CLAUDE.md', '.pkgmeta', '.gitignore', '.gitattributes', 'Thumbs.db', 'desktop.ini')

$stage = Join-Path ([IO.Path]::GetTempPath()) ("rqe-package-" + [guid]::NewGuid())
New-Item -ItemType Directory $stage | Out-Null
try {
    foreach ($a in $addons) {
        $src = Join-Path $addonsDir $a
        if (-not (Test-Path (Join-Path $src "$a.toc"))) { throw "Missing $a\$a.toc" }
        if (-not (Test-Path (Join-Path $src 'LICENSE-GPL-3.0.txt'))) { throw "Missing $a\LICENSE-GPL-3.0.txt" }

        Get-ChildItem $src -Recurse -File -Force | ForEach-Object {
            $rel   = $_.FullName.Substring($src.Length + 1)
            $parts = $rel -split '[\\/]'
            if ($parts[0] -in $excludeDirs) { return }
            if ($_.Name -in $excludeFiles)  { return }
            if ($_.Name -match '\.(bak|tmp|orig|swp)$' -or $_.Name -like '~*') { return }
            $dst = Join-Path (Join-Path $stage $a) $rel
            New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
            Copy-Item $_.FullName $dst
        }
    }

    New-Item -ItemType Directory -Force $outDir | Out-Null
    $zip = Join-Path $outDir "RavenquillExpedition-$Version.zip"
    if (Test-Path $zip) { Remove-Item $zip }

    # Build the zip with forward-slash entry names (Compress-Archive on Windows PowerShell writes backslashes,
    # which some unzip tools and the CurseForge app mishandle).
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $fs = [IO.File]::Open($zip, 'CreateNew')
    $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
            $entry = $_.FullName.Substring($stage.Length + 1) -replace '\\', '/'
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $_.FullName, $entry, 'Optimal')
        }
    } finally { $za.Dispose(); $fs.Dispose() }

    $count = (Get-ChildItem $stage -Recurse -File).Count
    "Built $zip"
    "  addons: $($addons -join ', ')"
    "  files:  $count, size: {0:N0} bytes" -f (Get-Item $zip).Length
} finally {
    Remove-Item $stage -Recurse -Force
}
