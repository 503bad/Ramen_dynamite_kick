# 配布物(dist\RamenRanbu_<版>\ と .zip)を作る。開発者用。
# UTF-8(BOM 付き)で保存すること。
#
#   powershell -ExecutionPolicy Bypass -File scripts\make_package.ps1 [-Version 0.1.0]

[CmdletBinding()]
param(
    [string]$Version = 'dev'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Repo = Split-Path -Parent $PSScriptRoot
$UE4SSZipName = 'UE4SS_v3.0.1-1183-gcdbc0b66.zip'
$UE4SSSha256 = 'e4a47e23e2eeb8379c4fc388d1b1686f01c6c5930d84a2ee4a6a9574b274e681'
$UE4SSZip = Join-Path $Repo "third_party\ue4ss\$UE4SSZipName"
# zip から取り出すもの(それ以外の付属 MOD 等は入れない。理由は third_party\ue4ss\README.md)
$UE4SSKeep = @('dwmapi.dll', 'ue4ss/UE4SS.dll', 'ue4ss/UE4SS-settings.ini', 'ue4ss/LICENSE')

$Out = Join-Path $Repo "dist\RamenRanbu_$Version"
$OutZip = "$Out.zip"

function Copy-To([string]$src, [string]$dstRel) {
    $dst = Join-Path $Out $dstRel
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst
}

# ---- UE4SS の検証
if (-not (Test-Path -LiteralPath $UE4SSZip)) {
    throw "UE4SS の zip がありません: $UE4SSZip(third_party\ue4ss\README.md を参照)"
}
$hash = (Get-FileHash -LiteralPath $UE4SSZip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $UE4SSSha256) { throw "UE4SS の zip の SHA-256 が一致しません: $hash" }

# ---- 出力先を作り直す
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
if (Test-Path -LiteralPath $OutZip) { Remove-Item -LiteralPath $OutZip -Force }
New-Item -ItemType Directory -Path $Out | Out-Null

# ---- インストーラ
Copy-To (Join-Path $Repo 'scripts\install.bat') 'install.bat'
Copy-To (Join-Path $Repo 'scripts\uninstall.bat') 'uninstall.bat'
Copy-To (Join-Path $Repo 'scripts\ramen_ranbu_setup.ps1') 'scripts\ramen_ranbu_setup.ps1'

# ---- UE4SS(必要なファイルだけ)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($UE4SSZip)
try {
    foreach ($name in $UE4SSKeep) {
        $e = $zip.GetEntry($name)
        if (-not $e) { throw "UE4SS の zip に $name がありません" }
        $dst = Join-Path $Out ('ue4ss_bundle\' + ($name -replace '/', '\'))
        $dir = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $false)
    }
} finally { $zip.Dispose() }
$modsTxt = Join-Path $Out 'ue4ss_bundle\ue4ss\Mods\mods.txt'
New-Item -ItemType Directory -Path (Split-Path $modsTxt -Parent) | Out-Null
# UE4SS 付属のサンプル MOD(チート・コンソール有効化など)は同梱せず、すべて無効にしておく。
# RamenRanbu は自分のフォルダの enabled.txt で有効になるので、ここに書く必要はない。
[System.IO.File]::WriteAllText($modsTxt,
    "; RamenRanbu bundle: UE4SS sample mods are not included and are disabled.`r`n" +
    "CheatManagerEnablerMod : 0`r`nConsoleCommandsMod : 0`r`nConsoleEnablerMod : 0`r`nSplitScreenMod : 0`r`n" +
    "LineTraceMod : 0`r`nBPML_GenericFunctions : 0`r`nBPModLoaderMod : 0`r`nKeybinds : 0`r`n")

# ---- MOD 本体(Lua。開発用の dev フォルダは入れない)
$modSrc = Join-Path $Repo 'mod\RamenRanbu'
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $modSrc 'Scripts') -File -Filter '*.lua')) {
    if ($f.Name -eq 'dev.lua') { continue }
    Copy-To $f.FullName ("mod\RamenRanbu\Scripts\" + $f.Name)
}
Copy-To (Join-Path $modSrc 'config.txt') 'mod\RamenRanbu\config.txt'

# ---- ドキュメントとライセンス
Copy-To (Join-Path $Repo 'README.md') 'README.md'
Copy-To (Join-Path $Repo 'third_party\ue4ss\LICENSE') 'licenses\UE4SS.txt'
Copy-To (Join-Path $Repo 'third_party\ue4ss\README.md') 'licenses\UE4SS_bundle_README.md'
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Repo 'third_party\ue4ss\licenses') -File)) {
    Copy-To $f.FullName ("licenses\UE4SS_deps\" + $f.Name)
}

Compress-Archive -Path (Join-Path $Out '*') -DestinationPath $OutZip
Write-Host "作成しました: $Out"
Write-Host "             $OutZip"
