# Hermetic Android APK build on a Windows host, modelled on the Minitanks ship-kit (tools/ship-kit/build/build-android.ps1).
#   toolchain discovery (Godot editor, JDK 17, Android SDK build-tools) -> debug keystore (created when missing)
#   -> staged copy of the project (.tools/build-android-project) -> staged export_presets.cfg patch (versionCode, package, stock
#   templates) -> self-contained editor copy with its own editor settings (the user's Godot settings are never touched)
#   -> import (twice on a fresh stage) -> export -> APK checks (manifest, native lib, pack, apksigner, aapt) -> build_record.json
#
#   powershell -ExecutionPolicy Bypass -File tools/build_android.ps1 [-Mode debug|release] [-PackageId com.x.y] [-VersionCode N] [-DryRun]
# debug   (default) debug export signed with the standard Android debug keystore (created under .tools/android-editor/).
# release release export; signing key comes ONLY from the environment (never a file in the repo):
#           GOSPORTS_KEYSTORE_PATH, GOSPORTS_KEYSTORE_ALIAS, GOSPORTS_KEYSTORE_PASS
# Toolchain lookup (first hit wins): -JavaHome / -AndroidSdk / -GodotBin, $env:JAVA_HOME / ANDROID_HOME / GODOT_BIN, the Minitanks
# toolchain H:\GDP\mini-tanks\.tools\android-setup\{jdk,sdk}, Android Studio's jbr, %LOCALAPPDATA%\Android\Sdk.
# Keep this file ASCII (PowerShell 5.1 reads BOM-less scripts in the ANSI code page).
param(
    [ValidateSet('debug', 'release')][string]$Mode = 'debug',
    [string]$GodotBin = '',
    [string]$JavaHome = '',
    [string]$AndroidSdk = '',
    [string]$PackageId = 'com.gosports.volleyball.dev',
    [long]$VersionCode = 0,
    [string]$Preset = 'Android',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tools = Join-Path $root '.tools'
$stage = Join-Path $tools 'build-android-project'
$editorDir = Join-Path $tools 'android-editor'
$outDir = Join-Path $root 'build/android'
$logDir = $tools

function Invoke-Native([string]$What, [scriptblock]$Block) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $Block; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $saved }
    if ($code -ne 0) { throw "$What failed (exit $code)." }
    return $output
}
function First-Existing([string[]]$Candidates, [string]$Probe) {
    foreach ($c in $Candidates) { if ($c -and (Test-Path -LiteralPath (Join-Path $c $Probe))) { return [IO.Path]::GetFullPath($c) } }
    return ''
}

# ---- toolchain ----
$godot = $GodotBin
if (-not $godot) { $godot = $env:GODOT_BIN }
if (-not $godot) { $godot = 'D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $godot)) { throw "No Godot editor at $godot (pass -GodotBin)." }
$godot = [IO.Path]::GetFullPath($godot)
$versionLine = ((Invoke-Native 'godot --version' { & $godot --version }) | Select-Object -Last 1).Trim()
$tag = ($versionLine -split '\.' | Select-Object -First 4) -join '.'
$tag = ($versionLine -replace '^(\d+\.\d+(\.\d+)?\.[a-z]+).*$', '$1')
$short = ($tag -split '\.' | Select-Object -First 2) -join '.'
$mt = 'H:/GDP/mini-tanks/.tools/android-setup'
$jdk = First-Existing @($JavaHome, $env:JAVA_HOME, "$mt/jdk", 'C:/Program Files/Android/Android Studio/jbr') 'bin/keytool.exe'
if (-not $jdk) { throw 'No JDK 17 found (need bin/keytool.exe): pass -JavaHome.' }
$sdk = First-Existing @($AndroidSdk, $env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$mt/sdk", (Join-Path $env:LOCALAPPDATA 'Android/Sdk')) 'build-tools'
if (-not $sdk) { throw 'No Android SDK with build-tools found: pass -AndroidSdk.' }
$bt = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'apksigner.bat') } |
    Sort-Object { $v = [version]'0.0'; [void][version]::TryParse(($_.Name -replace '[^0-9.].*$', ''), [ref]$v); $v } | Select-Object -Last 1
if (-not $bt) { throw "No build-tools with apksigner.bat under $sdk/build-tools." }
$apksigner = Join-Path $bt.FullName 'apksigner.bat'
$aapt = Join-Path $bt.FullName 'aapt.exe'
$templates = Join-Path $env:APPDATA "Godot/export_templates/$tag"
$tplDebug = Join-Path $templates 'android_debug.apk'
$tplRelease = Join-Path $templates 'android_release.apk'
foreach ($t in @($tplDebug, $tplRelease)) { if (-not (Test-Path -LiteralPath $t)) { throw "Stock Android export template missing: $t" } }

# ---- version ----
$epoch = [DateTime]::SpecifyKind([DateTime]'2025-01-01', 'Utc')
$now = [DateTime]::UtcNow
$build = $now.ToString('yyyyMMddHHmm')
if ($VersionCode -le 0) { $VersionCode = [long][math]::Floor(($now - $epoch).TotalMinutes) }
$settingsText = [IO.File]::ReadAllText((Join-Path $root 'project.godot'))
$verName = '1.0.0'
if ($settingsText -match 'config/version="([^"]+)"') { $verName = $Matches[1] }
$commit = ''
try { $commit = (& git -C $root rev-parse --short HEAD 2>$null) } catch { }
if (-not $commit) { $commit = 'nogit' }

Write-Host "android: editor $versionLine; JDK $jdk; SDK $sdk (build-tools $($bt.Name))"
Write-Host "android: $Mode build $build  package $PackageId  version $verName  versionCode $VersionCode"
if ($DryRun) { Write-Host 'dry run: nothing built.'; return }

# ---- signing ----
$debugKeystore = Join-Path $editorDir 'debug.keystore'
New-Item -ItemType Directory -Force -Path $editorDir | Out-Null
if ($Mode -eq 'debug') {
    if (-not (Test-Path -LiteralPath $debugKeystore)) {
        [void](Invoke-Native 'keytool (debug keystore)' { & (Join-Path $jdk 'bin/keytool.exe') -genkeypair -keystore $debugKeystore -storepass android -keypass android `
            -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US' 2>&1 })
        Write-Host "android: created debug keystore $debugKeystore"
    }
} else {
    foreach ($n in 'GOSPORTS_KEYSTORE_PATH', 'GOSPORTS_KEYSTORE_ALIAS', 'GOSPORTS_KEYSTORE_PASS') {
        if (-not [Environment]::GetEnvironmentVariable($n)) { throw "Release signing needs `$env:$n (keep the keystore outside the repository)." }
    }
}

# ---- stage ----
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$ErrorActionPreference = 'Continue'
& robocopy $root $stage /MIR /XD '.git' '.godot' '.tools' 'build' 'docs' 'tools' /XF '*.log' '.gitignore' /NFL /NDL /NJH /NJS /NP | Out-Null
$copyExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($copyExit -ge 8) { throw "Staging copy failed (robocopy exit $copyExit)." }
# robocopy /MIR deletes the stage's .godot import cache when it is not in the source: keep it by excluding it on both sides
# (the XD above excludes .godot from the mirror, so an existing stage cache survives).

# ---- patch staged presets ----
$presets = Join-Path $stage 'export_presets.cfg'
$text = [IO.File]::ReadAllText($presets)
$start = $text.IndexOf('name="' + $Preset + '"')
if ($start -lt 0) { throw "Preset '$Preset' not found in export_presets.cfg." }
$before = $text.Substring(0, $start)
$sectionStart = $before.LastIndexOf('[preset.')
$next = $text.IndexOf("`n[preset.", $start)
$headEnd = $text.IndexOf("[preset.", $start)
# options section of this preset
$optMatch = [regex]::Match($text.Substring($sectionStart), '\[preset\.(\d+)\.options\]')
if (-not $optMatch.Success) { throw 'Android options section not found.' }
$optPos = $sectionStart + $optMatch.Index + $optMatch.Length
$optEnd = $text.IndexOf("`n[preset.", $optPos)
if ($optEnd -lt 0) { $optEnd = $text.Length }
$opts = $text.Substring($optPos, $optEnd - $optPos)
function Set-Opt([string]$Opts, [string]$Key, [string]$Value) {
    $rx = '(?m)^' + [regex]::Escape($Key) + '=.*$'
    if ([regex]::IsMatch($Opts, $rx)) { return [regex]::Replace($Opts, $rx, { param($m) $Key + '=' + $Value }) }
    return $Opts.TrimEnd() + "`n" + $Key + '=' + $Value + "`n"
}
$opts = Set-Opt $opts 'version/code' ([string]$VersionCode)
$opts = Set-Opt $opts 'version/name' ('"' + $verName + '"')
$opts = Set-Opt $opts 'package/unique_name' ('"' + $PackageId + '"')
$opts = Set-Opt $opts 'custom_template/debug' ('"' + ($tplDebug -replace '\\', '/') + '"')
$opts = Set-Opt $opts 'custom_template/release' ('"' + ($tplRelease -replace '\\', '/') + '"')
$opts = Set-Opt $opts 'package/signed' 'true'
$patched = $text.Substring(0, $optPos) + $opts + $text.Substring($optEnd)
[IO.File]::WriteAllText($presets, $patched, (New-Object Text.UTF8Encoding($false)))

# ---- self-contained editor copy ----
$godotName = Split-Path -Leaf $godot
Copy-Item -LiteralPath $godot -Destination (Join-Path $editorDir $godotName) -Force
$guiName = $godotName -replace '_console\.exe$', '.exe'
if ($guiName -ne $godotName) { Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $godot) $guiName) -Destination (Join-Path $editorDir $guiName) -Force }
Set-Content -LiteralPath (Join-Path $editorDir '._sc_') -Value '' -Encoding Ascii
$ed = Join-Path $editorDir 'editor_data'
New-Item -ItemType Directory -Force -Path $ed | Out-Null
function Q([string]$p) { return '"' + ($p -replace '\\', '/') + '"' }
$settings = @('[gd_resource type="EditorSettings" format=3]', '', '[resource]',
    ('export/android/java_sdk_path = ' + (Q $jdk)), ('export/android/android_sdk_path = ' + (Q $sdk)),
    ('export/android/debug_keystore = ' + (Q $debugKeystore)), 'export/android/debug_keystore_user = "androiddebugkey"', 'export/android/debug_keystore_pass = "android"')
[IO.File]::WriteAllText((Join-Path $ed "editor_settings-$short.tres"), ($settings -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
$sc = Join-Path $editorDir $godotName

$secretEnv = @('GODOT_ANDROID_KEYSTORE_DEBUG_PATH', 'GODOT_ANDROID_KEYSTORE_DEBUG_USER', 'GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD',
    'GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')
$saved = @{ JAVA_HOME = $env:JAVA_HOME; ANDROID_HOME = $env:ANDROID_HOME; ANDROID_SDK_ROOT = $env:ANDROID_SDK_ROOT }
$tempApk = ''
try {
    $env:JAVA_HOME = $jdk; $env:ANDROID_HOME = $sdk; $env:ANDROID_SDK_ROOT = $sdk
    # ---- import ----
    $importLog = Join-Path $logDir 'android-import.log'
    $ErrorActionPreference = 'Continue'
    if (-not (Test-Path -LiteralPath (Join-Path $stage '.godot/imported'))) {
        & $sc --headless --editor --path $stage --import --log-file (Join-Path $logDir 'android-import-first.log') *> $null
    }
    & $sc --headless --editor --path $stage --import --log-file $importLog *> $null
    $importExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($importExit -ne 0) { throw "Godot import failed (log $importLog)." }
    if (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|Parse Error') { throw "Godot import reported script errors (log $importLog)." }

    # ---- export ----
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $tempApk = Join-Path $outDir ('.building-' + $Mode + '.apk')
    Remove-Item -Force -LiteralPath $tempApk -ErrorAction SilentlyContinue
    if ($Mode -eq 'debug') {
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $debugKeystore
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = 'androiddebugkey'
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = 'android'
    } else {
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $env:GOSPORTS_KEYSTORE_PATH
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $env:GOSPORTS_KEYSTORE_ALIAS
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $env:GOSPORTS_KEYSTORE_PASS
    }
    $exportLog = Join-Path $logDir 'android-export.log'
    $flag = if ($Mode -eq 'debug') { '--export-debug' } else { '--export-release' }
    $ErrorActionPreference = 'Continue'
    & $sc --headless --log-file $exportLog --path $stage $flag $Preset $tempApk *> $null
    $exportExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    foreach ($n in $secretEnv) { Remove-Item "Env:$n" -ErrorAction SilentlyContinue }
    if ($exportExit -ne 0) { throw "Android export failed (log $exportLog)." }
    if (-not (Test-Path -LiteralPath $tempApk)) { throw "Godot produced no APK (log $exportLog)." }

    # ---- APK checks ----
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($tempApk)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
        if ($entries -notcontains 'AndroidManifest.xml') { throw 'APK has no AndroidManifest.xml.' }
        $libs = @($entries | Where-Object { $_ -match '^lib/[^/]+/libgodot_android\.so$' })
        if ($libs.Count -eq 0) { throw 'APK has no lib/<abi>/libgodot_android.so.' }
        $pack = @($entries | Where-Object { $_ -match '^assets/[^/]+\.(sparsepck|pck)$' }) | Select-Object -First 1
        if (-not $pack) { throw 'APK carries no game pack.' }
        Write-Host "android: APK structure ok ($($libs -join ', '); $pack)"
    } finally { $zip.Dispose() }
    $signOut = Invoke-Native 'apksigner verify' { & $apksigner verify --verbose $tempApk 2>&1 }
    $schemes = @($signOut | Where-Object { "$_" -match 'Verified using v\d.*true' } | ForEach-Object { ("$_" -replace '^Verified using ', '' -replace ' scheme.*', '') })
    Write-Host "android: apksigner verify ok ($($schemes -join ', '))"
    if (Test-Path -LiteralPath $aapt) {
        # aapt exits with 1 on harmless resource warnings: judge by the output instead of the exit code
        $ErrorActionPreference = 'Continue'
        $badge = @(& $aapt dump badging $tempApk 2>$null)
        if (-not ($badge | Where-Object { $_ -match '^package: ' })) { $badge = @(& (Join-Path $bt.FullName 'aapt2.exe') dump badging $tempApk 2>$null) }
        $ErrorActionPreference = 'Stop'
        $pkgLine = [string]($badge | Where-Object { $_ -match '^package: ' } | Select-Object -First 1)
        if ($pkgLine -notmatch ("name='" + [regex]::Escape($PackageId) + "'") -or $pkgLine -notmatch ("versionCode='" + $VersionCode + "'")) {
            throw "APK identity mismatch: $pkgLine"
        }
        Write-Host "android: $pkgLine"
    }
    $apkPath = Join-Path $outDir ("GoSports-$Mode.apk")
    Move-Item -Force -LiteralPath $tempApk -Destination $apkPath
    $tempApk = ''
    $hash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLower()
    $record = [ordered]@{
        platform = 'android'; mode = $Mode; package_id = $PackageId; version = $verName; version_code = $VersionCode; build = $build
        engine = $versionLine; commit = $commit; built_at = $now.ToString('o'); apk = (Split-Path -Leaf $apkPath)
        size = (Get-Item -LiteralPath $apkPath).Length; sha256 = $hash; encrypted = $false
        validation = 'manifest+native-lib+pack+apksigner+aapt'
    }
    [IO.File]::WriteAllText((Join-Path $outDir 'build_record.json'), ($record | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Write-Host ("android: {0} ({1:N1} MiB, sha256 {2})" -f $apkPath, ((Get-Item -LiteralPath $apkPath).Length / 1MB), $hash)
    Write-Host 'ANDROID_BUILD_OK (APK structure / signature only: runtime needs a phone - adb install -r)'
} finally {
    foreach ($n in $secretEnv) { Remove-Item "Env:$n" -ErrorAction SilentlyContinue }
    foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item "Env:$k" $saved[$k] } }
    if ($tempApk) { Remove-Item -Force -LiteralPath $tempApk -ErrorAction SilentlyContinue }
}
