param(
    [string]$Version
)
$ErrorActionPreference = 'Stop'

$repo   = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $repo 'dist'

$addons = git -C $repo ls-files '*.toc' | ForEach-Object { if ($_ -match '^(RavenquillExpedition[^/]*)/\1\.toc$') { $Matches[1] } } |
    Where-Object { $_ -ne 'RavenquillExpedition_Dev' }
if (-not $addons) { throw "No tracked RavenquillExpedition* addon folders in $repo" }

if (-not $Version) {
    $m = Select-String -Path (Join-Path $repo 'RavenquillExpedition\RavenquillExpedition.toc') -Pattern '^## Version:\s*(\S+)'
    $Version = $m.Matches[0].Groups[1].Value
}
if ($Version -notmatch '^[0-9A-Za-z.\-]+$') { throw "Unexpected version '$Version'" }

$excludeDirs  = @('dev', '.git', '.github', '.vscode', '.idea', '.claude')
$excludeFiles = @('HANDOFF.md', 'PLAN.md', 'CLAUDE.md', '.pkgmeta', '.gitignore', '.gitattributes', 'Thumbs.db', 'desktop.ini')

$stage = Join-Path ([IO.Path]::GetTempPath()) ("rqe-package-" + [guid]::NewGuid())
New-Item -ItemType Directory $stage | Out-Null
try {
    foreach ($a in $addons) {
        $src = Join-Path $repo $a
        if (-not (Test-Path (Join-Path $src "$a.toc"))) { throw "Missing $a\$a.toc" }

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

        $toc = Join-Path (Join-Path $stage $a) "$a.toc"
        $text = [IO.File]::ReadAllText($toc)
        if ($text -notmatch '(?m)^## Version:') { throw "$a.toc has no ## Version line" }
        $text = [regex]::Replace($text, '(?m)^## Version:.*$', "## Version: $Version")
        [IO.File]::WriteAllText($toc, $text, (New-Object Text.UTF8Encoding $false))
    }

    New-Item -ItemType Directory -Force $outDir | Out-Null
    $zip = Join-Path $outDir "RavenquillExpedition-$Version.zip"
    if (Test-Path $zip) { Remove-Item $zip }

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
    "  addons:  $($addons -join ', ')"
    "  version: $Version (stamped into every .toc)"
    "  files:   $count, size: {0:N0} bytes" -f (Get-Item $zip).Length
} finally {
    Remove-Item $stage -Recurse -Force
}
