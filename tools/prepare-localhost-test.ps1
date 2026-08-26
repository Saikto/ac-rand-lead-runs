param(
    [string]$AssettoCorsaPath = 'N:\SteamLibrary\steamapps\common\assettocorsa',
    [string]$AssettoServerSource = (Join-Path $PSScriptRoot '..\.tmp\AssettoServer'),
    [string]$RuntimePath = (Join-Path $PSScriptRoot '..\.runtime\localhost-server'),
    [string]$RunFile = '',
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-SafeContentId([string]$Value, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Invalid $Label in run metadata: '$Value'"
    }
}

function Set-RuntimeJunction([string]$Path, [string]$Target) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        $actualTarget = @($item.Target)[0]
        if ($item.LinkType -ne 'Junction' -or (Resolve-FullPath $actualTarget) -ne (Resolve-FullPath $Target)) {
            throw "Runtime path already exists and is not the expected junction: $Path"
        }
        return
    }

    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
}

$repoRoot = Resolve-FullPath (Join-Path $PSScriptRoot '..')
$AssettoCorsaPath = Resolve-FullPath $AssettoCorsaPath
$AssettoServerSource = Resolve-FullPath $AssettoServerSource
$RuntimePath = Resolve-FullPath $RuntimePath

if (-not (Test-Path -LiteralPath $AssettoCorsaPath -PathType Container)) {
    throw "Assetto Corsa folder does not exist: $AssettoCorsaPath"
}

if ([string]::IsNullOrWhiteSpace($RunFile)) {
    $runsRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'Assetto Corsa\ac-random-lead-runs\runs'
    $latest = Get-ChildItem -LiteralPath $runsRoot -Filter latest.json -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw "No latest.json found below: $runsRoot"
    }
    $RunFile = $latest.FullName
}

$RunFile = Resolve-FullPath $RunFile
$run = Get-Content -LiteralPath $RunFile -Raw | ConvertFrom-Json
if ($run.version -notin @(1, 2) -or $run.frames.Count -lt 2 -or [double]$run.duration -le 0) {
    throw "Run is not a supported non-empty v1/v2 recording: $RunFile"
}

Assert-SafeContentId $run.track 'track ID'
Assert-SafeContentId $run.layout 'layout ID'
Assert-SafeContentId $run.car 'car ID'

$trackPath = Join-Path $AssettoCorsaPath "content\tracks\$($run.track)"
$carPath = Join-Path $AssettoCorsaPath "content\cars\$($run.car)"
if (-not (Test-Path -LiteralPath $trackPath -PathType Container)) {
    throw "Recorded track is not installed: $trackPath"
}
if (-not (Test-Path -LiteralPath $carPath -PathType Container)) {
    throw "Recorded car is not installed: $carPath"
}

$skin = Get-ChildItem -LiteralPath (Join-Path $carPath 'skins') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name |
    Select-Object -First 1
if (-not $skin) {
    throw "Recorded car has no installed skins: $carPath"
}

& (Join-Path $PSScriptRoot 'build-server-plugin.ps1') -AssettoServerSource $AssettoServerSource -Configuration $Configuration

$cfgPath = Join-Path $RuntimePath 'cfg'
$pluginPath = Join-Path $RuntimePath 'plugins\RandomLeadServerPlugin'
New-Item -ItemType Directory -Path $cfgPath -Force | Out-Null
New-Item -ItemType Directory -Path $pluginPath -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $RuntimePath 'logs') -Force | Out-Null

Set-RuntimeJunction (Join-Path $RuntimePath 'content') (Join-Path $AssettoCorsaPath 'content')
Set-RuntimeJunction (Join-Path $RuntimePath 'system') (Join-Path $AssettoCorsaPath 'system')

$pluginDll = Join-Path $repoRoot "server-plugin\bin\$Configuration\net9.0\RandomLeadServerPlugin.dll"
if (-not (Test-Path -LiteralPath $pluginDll -PathType Leaf)) {
    throw "Plugin build output is missing: $pluginDll"
}
New-Item -ItemType Directory -Path (Join-Path $AssettoServerSource "AssettoServer\bin\$Configuration\net9.0\plugins") -Force | Out-Null
Copy-Item -LiteralPath $pluginDll -Destination (Join-Path $pluginPath 'RandomLeadServerPlugin.dll') -Force

$serverCfg = @"
[SERVER]
NAME=AC Random Lead Runs (localhost)
CONFIG_TRACK=$($run.layout)
TRACK=$($run.track)
SUN_ANGLE=6
PASSWORD=
ADMIN_PASSWORD=
UDP_PORT=9600
TCP_PORT=9600
HTTP_PORT=8081
MAX_CLIENTS=2
CLIENT_SEND_INTERVAL_HZ=50
LOOP_MODE=1
FUEL_RATE=0
DAMAGE_MULTIPLIER=0
TYRE_WEAR_RATE=0
ALLOWED_TYRES_OUT=-1
ABS_ALLOWED=1
TC_ALLOWED=1
STABILITY_ALLOWED=0
AUTOCLUTCH_ALLOWED=1
TYRE_BLANKETS_ALLOWED=1
FORCE_VIRTUAL_MIRROR=0
REGISTER_TO_LOBBY=0
TIME_OF_DAY_MULT=1
WELCOME_MESSAGE=

[PRACTICE]
INFINITE=1

[DYNAMIC_TRACK]
SESSION_START=100

[WEATHER_0]
GRAPHICS=3_clear_type=15
BASE_TEMPERATURE_AMBIENT=18
BASE_TEMPERATURE_ROAD=24
VARIATION_AMBIENT=0
VARIATION_ROAD=0
WIND_BASE_SPEED_MIN=0
WIND_BASE_SPEED_MAX=0
WIND_BASE_DIRECTION=0
WIND_VARIATION_DIRECTION=0
"@

$entryList = @"
[CAR_0]
MODEL=$($run.car)
SKIN=$($skin.Name)
GUID=

[CAR_1]
MODEL=$($run.car)
SKIN=$($skin.Name)
GUID=1
"@

$escapedRunFile = $RunFile.Replace("'", "''")
$extraCfg = @"
MinimumCSPVersion: 2651
UseSteamAuth: false
EnableServerDetails: false
EnableWeatherFx: false
EnableAi: false
EnablePlugins:
  - RandomLeadServerPlugin
EnableCustomUpdate: true
EnableUPnP: false
IgnoreConfigurationErrors:
  MissingCarChecksums: true
  MissingTrackParams: true
  UnsafeAdminWhitelist: false
"@

$pluginCfg = @"
Enabled: true
LeaderSessionId: 1
RunFile: '$escapedRunFile'
StartDelaySeconds: 5
Loop: true
LoopDelaySeconds: 3
"@

Set-Content -LiteralPath (Join-Path $cfgPath 'server_cfg.ini') -Value $serverCfg -Encoding utf8NoBOM
Set-Content -LiteralPath (Join-Path $cfgPath 'entry_list.ini') -Value $entryList -Encoding utf8NoBOM
Set-Content -LiteralPath (Join-Path $cfgPath 'extra_cfg.yml') -Value $extraCfg -Encoding utf8NoBOM
Set-Content -LiteralPath (Join-Path $cfgPath 'plugin_random_lead_server_cfg.yml') -Value $pluginCfg -Encoding utf8NoBOM

$runtimeInfo = [ordered]@{
    generatedAt = [DateTime]::UtcNow.ToString('o')
    runFile = $RunFile
    runId = [string]$run.id
    duration = [double]$run.duration
    track = [string]$run.track
    layout = [string]$run.layout
    car = [string]$run.car
    skin = $skin.Name
    address = '127.0.0.1:9600'
    logs = (Join-Path $RuntimePath 'logs')
}
$runtimeInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $RuntimePath 'runtime-info.json') -Encoding utf8NoBOM

Write-Output "Localhost fixture prepared: $RuntimePath"
Write-Output "Run: $($run.id) ($([Math]::Round([double]$run.duration, 2)) s)"
Write-Output "Content: $($run.track) / $($run.layout) / $($run.car)"
Write-Output 'Connect address: 127.0.0.1:9600'
Write-Output "Logs: $(Join-Path $RuntimePath 'logs')"
