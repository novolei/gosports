# Windows desktop build with the AES-256 ENCRYPTED pack, the same scheme as Minitanks (tools/build-windows.ps1):
#   staged copy of the project (.tools/build-windows-project) -> staged export_presets.cfg patch (custom release template + encryption
#   switches) -> import (twice on a fresh stage) -> export-release with GODOT_SCRIPT_ENCRYPTION_KEY in the environment of the export
#   process only -> artifact check (embedded pack header flag, engine version of the exe) -> build/windows/GoSports.exe
#
#   powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1 [-EncTemplates <dir>] [-Plain] [-DryRun]
# Template + key: -EncTemplates, else $env:GOSPORTS_ENC_TEMPLATES, else H:/GDP/mini-tanks/.tools/encrypted-templates
# (windows_release_x86_64.exe + windows_release_x86_64.key; the template also needs its ..._console.exe sibling for the console wrapper).
# A missing template or key is an ERROR - there is no silent fallback to a plain build; -Plain asks for one explicitly (local debugging only).
# Keep this file ASCII (PowerShell 5.1 reads BOM-less scripts in the ANSI code page).
param(
    [string]$GodotBin = '',
    [string]$EncTemplates = '',
    [string]$Preset = 'Windows Desktop',
    [switch]$Plain,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tools = Join-Path $root '.tools'
$stage = Join-Path $tools 'build-windows-project'
$outDir = Join-Path $root 'build/windows'
$logDir = $tools

function Invoke-Native([string]$What, [scriptblock]$Block) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $Block; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $saved }
    if ($code -ne 0) { throw "$What failed (exit $code)." }
    return $output
}

# ---- toolchain / template / key ----
$godot = $GodotBin
if (-not $godot) { $godot = $env:GODOT_BIN }
if (-not $godot) { $godot = 'D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $godot)) { throw "No Godot editor at $godot (pass -GodotBin)." }
$godot = [IO.Path]::GetFullPath($godot)
$versionLine = ((Invoke-Native 'godot --version' { & $godot --version }) | Select-Object -Last 1).Trim()
$engineStamp = ($versionLine -replace '^(\d+\.\d+\.\d+).*$', '$1')
$encKey = ''
$tplEnc = ''
if (-not $Plain) {
    if (-not $EncTemplates) { $EncTemplates = $env:GOSPORTS_ENC_TEMPLATES }
    if (-not $EncTemplates) { $EncTemplates = 'H:/GDP/mini-tanks/.tools/encrypted-templates' }
    $tplEnc = [IO.Path]::GetFullPath((Join-Path $EncTemplates 'windows_release_x86_64.exe'))
    $keyFile = Join-Path $EncTemplates 'windows_release_x86_64.key'
    if (-not (Test-Path -LiteralPath $tplEnc)) { throw "Encrypted Windows template missing: $tplEnc" }
    if (-not (Test-Path -LiteralPath $keyFile)) { throw "Encryption key file missing: $keyFile" }
    $encKey = ([IO.File]::ReadAllText($keyFile)).Trim()
    if ($encKey -notmatch '^[0-9A-Fa-f]{64}$') { throw 'The encrypted-template key must be a 64-character hexadecimal AES-256 key.' }
}
Write-Host "windows: editor $versionLine; encrypted = $(-not $Plain); template $tplEnc"
if ($DryRun) { Write-Host 'dry run: nothing built.'; return }

# ---- stage ----
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$ErrorActionPreference = 'Continue'
& robocopy $root $stage /MIR /XD '.git' '.godot' '.tools' 'build' 'docs' 'tools' /XF '*.log' '.gitignore' /NFL /NDL /NJH /NJS /NP | Out-Null
$copyExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($copyExit -ge 8) { throw "Staging copy failed (robocopy exit $copyExit)." }

# ---- patch the staged preset ----
$presets = Join-Path $stage 'export_presets.cfg'
$text = [IO.File]::ReadAllText($presets)
$start = $text.IndexOf('name="' + $Preset + '"')
if ($start -lt 0) { throw "Preset '$Preset' not found in export_presets.cfg." }
$sectionStart = $text.Substring(0, $start).LastIndexOf('[preset.')
$optMatch = [regex]::Match($text.Substring($sectionStart), '\[preset\.(\d+)\.options\]')
if (-not $optMatch.Success) { throw 'Options section not found.' }
$optPos = $sectionStart + $optMatch.Index + $optMatch.Length
$optEnd = $text.IndexOf("`n[preset.", $optPos)
if ($optEnd -lt 0) { $optEnd = $text.Length }
$head = $text.Substring(0, $optPos)
$opts = $text.Substring($optPos, $optEnd - $optPos)
function Set-Line([string]$Block, [string]$Key, [string]$Value) {
    $rx = '(?m)^' + [regex]::Escape($Key) + '=.*$'
    if (-not [regex]::IsMatch($Block, $rx)) { throw ("export_presets.cfg has no " + $Key) }
    $newLine = $Key + '=' + $Value
    return [regex]::Replace($Block, $rx, { param($m) $newLine })
}
$opts = Set-Line $opts 'debug/export_console_wrapper' '2'          # (a console exe next to the game exe, only used here to read the engine version)
if (-not $Plain) {
    $hs = $head.Substring($sectionStart)
    $hs = Set-Line $hs 'encryption_include_filters' '"*"'
    $hs = Set-Line $hs 'encrypt_pck' 'true'
    $hs = Set-Line $hs 'encrypt_directory' 'true'
    $head = $head.Substring(0, $sectionStart) + $hs
    $opts = Set-Line $opts 'custom_template/release' ('"' + ($tplEnc -replace '\\', '/') + '"')
}
[IO.File]::WriteAllText($presets, $head + $opts + $text.Substring($optEnd), (New-Object Text.UTF8Encoding($false)))

$tempExe = ''
try {
    # ---- import ----
    $importLog = Join-Path $logDir 'windows-import.log'
    $ErrorActionPreference = 'Continue'
    if (-not (Test-Path -LiteralPath (Join-Path $stage '.godot/imported'))) {
        & $godot --headless --editor --path $stage --import --log-file (Join-Path $logDir 'windows-import-first.log') *> $null
    }
    & $godot --headless --editor --path $stage --import --log-file $importLog *> $null
    $importExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($importExit -ne 0) { throw "Godot import failed (log $importLog)." }
    if (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|Parse Error') { throw "Godot import reported script errors (log $importLog)." }

    # ---- export (the key only lives in this process's environment) ----
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $tempDir = Join-Path $tools 'windows-out'
    Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $tempExe = Join-Path $tempDir 'GoSports.exe'
    if (-not $Plain) { $env:GODOT_SCRIPT_ENCRYPTION_KEY = $encKey }
    $exportLog = Join-Path $logDir 'windows-export.log'
    $ErrorActionPreference = 'Continue'
    & $godot --headless --log-file $exportLog --path $stage --export-release $Preset $tempExe *> $null
    $exportExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Remove-Item Env:GODOT_SCRIPT_ENCRYPTION_KEY -ErrorAction SilentlyContinue
    if ($exportExit -ne 0) { throw "Windows export failed (log $exportLog)." }
    if (-not (Test-Path -LiteralPath $tempExe)) { throw "Godot produced no exe (log $exportLog)." }

    # ---- artifact checks ----
    $enc = $false
    if (-not $Plain) {
        # the embedded pack starts with magic GDPC + format version + engine major/minor/patch, then the flags (offset 20, bit 0 =
        # encrypted directory). Find it by that signature (searching from the end), then read the flag.
        Add-Type -TypeDefinition @'
using System;
using System.IO;
public static class PckFind {
    public static long Find(string path, byte[] sig, int skip) {
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
            long len = fs.Length; int chunk = 1 << 22; var buf = new byte[chunk + sig.Length];
            for (long end = len; end > 0; end -= chunk) {
                long begin = Math.Max(0, end - chunk);
                int want = (int)Math.Min(len - begin, chunk + sig.Length - 1);
                fs.Seek(begin, SeekOrigin.Begin);
                int got = 0; while (got < want) { int n = fs.Read(buf, got, want - got); if (n <= 0) break; got += n; }
                for (int i = got - sig.Length; i >= 0; i--) {
                    if (buf[i] != sig[0]) continue;
                    bool ok = true;
                    for (int k = 0; k < sig.Length && ok; k++) { if (k >= 4 && k < 8) continue; if (buf[i + k] != sig[k]) ok = false; }
                    if (ok) return begin + i;
                }
            }
        }
        return -1;
    }
}
'@
        $ver = $engineStamp.Split('.')
        $sig = New-Object System.Collections.Generic.List[byte]
        $sig.AddRange([Text.Encoding]::ASCII.GetBytes('GDPC'))
        $sig.AddRange([byte[]](0, 0, 0, 0))                                    # pack format version (wildcard)
        foreach ($v in $ver) { $sig.AddRange([BitConverter]::GetBytes([uint32][int]$v)) }
        $pos = [PckFind]::Find($tempExe, $sig.ToArray(), 0)
        if ($pos -lt 0) { throw 'No embedded pack (GDPC + engine version) found in the exe.' }
        $fs = [IO.File]::OpenRead($tempExe)
        try { [void]$fs.Seek($pos, 'Begin'); $hdr = [byte[]]::new(24); [void]$fs.Read($hdr, 0, 24) } finally { $fs.Dispose() }
        if (([BitConverter]::ToUInt32($hdr, 20) -band 1) -eq 0) { throw 'GoSports.exe pack is NOT encrypted although the encrypted template is configured.' }
        $enc = $true
        Write-Host ("windows: encryption verified (pack header at {0}, directory flag set)" -f $pos)
    }
    # the exported binary must be the stamped engine
    $consoleExe = Join-Path $tempDir 'GoSports.console.exe'
    if (-not (Test-Path -LiteralPath $consoleExe)) { throw 'The console wrapper was not exported (the template needs its _console.exe sibling).' }
    $exeVer = ((Invoke-Native 'exe --version' { & $consoleExe --version }) | Select-Object -Last 1).Trim()
    if (-not $exeVer.StartsWith($engineStamp)) { throw "Exported exe reports engine '$exeVer', the editor is '$versionLine'." }
    Write-Host "windows: exported exe engine $exeVer"

    # ---- publish to build/windows ----
    foreach ($f in Get-ChildItem -LiteralPath $tempDir -File | Where-Object { $_.Name -notlike '*.console.exe' }) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $outDir $f.Name) -Force }
    $final = Join-Path $outDir 'GoSports.exe'
    $hash = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash.ToLower()
    $commit = ''
    try { $commit = (& git -C $root rev-parse --short HEAD 2>$null) } catch { }
    $record = [ordered]@{
        platform = 'windows'; encrypted = $enc; engine = $versionLine; commit = $commit; built_at = [DateTime]::UtcNow.ToString('o')
        exe = 'GoSports.exe'; size = (Get-Item -LiteralPath $final).Length; sha256 = $hash
    }
    [IO.File]::WriteAllText((Join-Path $outDir 'build_record.json'), ($record | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Write-Host ("windows: {0} ({1:N1} MiB, sha256 {2})" -f $final, ((Get-Item -LiteralPath $final).Length / 1MB), $hash)
    Write-Host 'WINDOWS_BUILD_OK'
} finally {
    Remove-Item Env:GODOT_SCRIPT_ENCRYPTION_KEY -ErrorAction SilentlyContinue
}
