param(
    [string]$AssettoCorsaPath = 'N:\SteamLibrary\steamapps\common\assettocorsa',
    [string]$AssettoServerSource = (Join-Path $PSScriptRoot '..\.tmp\AssettoServer'),
    [string]$RuntimePath = (Join-Path $PSScriptRoot '..\.runtime\localhost-server'),
    [string]$RunFile = '',
    [string]$LauncherSettingsPath = '',
    [switch]$SkipPrepare
)

$ErrorActionPreference = 'Stop'
$AssettoServerSource = [System.IO.Path]::GetFullPath($AssettoServerSource)
$RuntimePath = [System.IO.Path]::GetFullPath($RuntimePath)

if (-not $SkipPrepare) {
    & (Join-Path $PSScriptRoot 'prepare-localhost-test.ps1') `
        -AssettoCorsaPath $AssettoCorsaPath `
        -AssettoServerSource $AssettoServerSource `
        -RuntimePath $RuntimePath `
        -RunFile $RunFile `
        -LauncherSettingsPath $LauncherSettingsPath
}

$tcpPort = 9600
$httpPort = 8081
if (-not [string]::IsNullOrWhiteSpace($LauncherSettingsPath)) {
    $launcherSettings = Get-Content -LiteralPath ([System.IO.Path]::GetFullPath($LauncherSettingsPath)) -Raw | ConvertFrom-Json
    $tcpPort = [int]$launcherSettings.tcpPort
    $httpPort = [int]$launcherSettings.httpPort
}
$tcpPorts = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Port
$udpPorts = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveUdpListeners().Port
if ($tcpPort -in $tcpPorts -or $tcpPort -in $udpPorts -or $httpPort -in $tcpPorts) {
    throw "Port $tcpPort or $httpPort is already in use. Stop the previous localhost server and retry."
}

$serverProject = Join-Path $AssettoServerSource 'AssettoServer\AssettoServer.csproj'
$serverCfg = Join-Path $RuntimePath 'cfg\server_cfg.ini'
$entryList = Join-Path $RuntimePath 'cfg\entry_list.ini'

Write-Output 'Starting AC Random Lead Runs localhost server.'
Write-Output "Connect in Content Manager to 127.0.0.1:$tcpPort."
Write-Output 'Keep this window open. Press Ctrl+C here to stop the server.'
Write-Output "Logs: $(Join-Path $RuntimePath 'logs')"

Push-Location $RuntimePath
try {
    dotnet run --project $serverProject --no-build -c Release -- `
        --plugins-from-workdir `
        -c $serverCfg `
        -e $entryList `
        --verbose
}
finally {
    Pop-Location
}
