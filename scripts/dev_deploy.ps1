# 開発用: mod\RamenRanbu をゲームの UE4SS Mods フォルダへコピーする(dev フォルダ付き = 開発用コマンド受付が有効)
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\Japanese Ramen Simulator",
    [switch]$NoDev
)
$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "..\mod\RamenRanbu"
$mods = Join-Path $GameDir "RealRamenSimulator\Binaries\Win64\ue4ss\Mods"
if (-not (Test-Path $mods)) { throw "UE4SS の Mods フォルダがありません: $mods" }
$dst = Join-Path $mods "RamenRanbu"
New-Item -ItemType Directory -Force (Join-Path $dst "Scripts") | Out-Null
Copy-Item (Join-Path $src "Scripts\*.lua") (Join-Path $dst "Scripts") -Force
Copy-Item (Join-Path $src "config.txt") $dst -Force
Set-Content -Path (Join-Path $dst "enabled.txt") -Value "" -Encoding ascii
$dev = Join-Path $dst "dev"
if ($NoDev) {
    if (Test-Path $dev) { Remove-Item -Recurse -Force $dev }
} else {
    New-Item -ItemType Directory -Force $dev | Out-Null
    Set-Content -Path (Join-Path $dev "enabled") -Value "" -Encoding ascii
}
Write-Host "deployed -> $dst"
