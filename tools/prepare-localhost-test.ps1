param(
    [string]$AssettoCorsaPath = 'N:\SteamLibrary\steamapps\common\assettocorsa',
    [string]$AssettoServerSource = (Join-Path $PSScriptRoot '..\.tmp\AssettoServer'),
    [string]$RuntimePath = (Join-Path $PSScriptRoot '..\.runtime\localhost-server'),
    [string]$RunFile = '',
    [string]$LauncherSettingsPath = '',
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Utf8NoBom([string]$Path, [string]$Value) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Get-CarGraphicsOffset([string]$CarPath) {
    $carIniPath = Join-Path $CarPath 'data\car.ini'
    if (-not (Test-Path -LiteralPath $carIniPath -PathType Leaf)) {
        return @(0.0, 0.0, 0.0)
    }

    $match = [regex]::Match(
        [System.IO.File]::ReadAllText($carIniPath),
        '(?im)^\s*GRAPHICS_OFFSET\s*=\s*([^;\r\n]+)')
    if (-not $match.Success) {
        return @(0.0, 0.0, 0.0)
    }

    $parts = $match.Groups[1].Value.Split(',')
    if ($parts.Count -ne 3) {
        throw "Invalid GRAPHICS_OFFSET in: $carIniPath"
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    return @(
        [double]::Parse($parts[0].Trim(), $culture),
        [double]::Parse($parts[1].Trim(), $culture),
        [double]::Parse($parts[2].Trim(), $culture)
    )
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

$launcherSettings = $null
if (-not [string]::IsNullOrWhiteSpace($LauncherSettingsPath)) {
    $LauncherSettingsPath = Resolve-FullPath $LauncherSettingsPath
    if (-not (Test-Path -LiteralPath $LauncherSettingsPath -PathType Leaf)) {
        throw "Launcher settings file does not exist: $LauncherSettingsPath"
    }
    $launcherSettings = Get-Content -LiteralPath $LauncherSettingsPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($RunFile)) {
        $RunFile = [string]$launcherSettings.runFile
    }
}

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
if ($run.version -notin @(1, 2, 3) -or $run.frames.Count -lt 2 -or [double]$run.duration -le 0) {
    throw "Run is not a supported non-empty v1/v2/v3 recording: $RunFile"
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

$leaderSkin = Get-ChildItem -LiteralPath (Join-Path $carPath 'skins') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name |
    Select-Object -First 1
if (-not $leaderSkin) {
    throw "Recorded car has no installed skins: $carPath"
}
$graphicsOffset = Get-CarGraphicsOffset $carPath

$playerCar = if ($launcherSettings -and -not [string]::IsNullOrWhiteSpace([string]$launcherSettings.playerCar)) {
    [string]$launcherSettings.playerCar
} else { [string]$run.car }
Assert-SafeContentId $playerCar 'player car ID'
$playerCarPath = Join-Path $AssettoCorsaPath "content\cars\$playerCar"
if (-not (Test-Path -LiteralPath $playerCarPath -PathType Container)) {
    throw "Selected player car is not installed: $playerCarPath"
}
$playerSkin = if ($launcherSettings -and -not [string]::IsNullOrWhiteSpace([string]$launcherSettings.playerSkin)) {
    [string]$launcherSettings.playerSkin
} else {
    (Get-ChildItem -LiteralPath (Join-Path $playerCarPath 'skins') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -First 1).Name
}
Assert-SafeContentId $playerSkin 'player skin ID'
if (-not (Test-Path -LiteralPath (Join-Path $playerCarPath "skins\$playerSkin") -PathType Container)) {
    throw "Selected player skin is not installed: $playerSkin"
}

$serverName = if ($launcherSettings -and -not [string]::IsNullOrWhiteSpace([string]$launcherSettings.serverName)) {
    ([string]$launcherSettings.serverName).Replace("`r", ' ').Replace("`n", ' ')
} else { 'AC Random Lead Runs (localhost)' }
$serverName = $serverName.Replace('=', '-').Trim()
$weather = if ($launcherSettings -and -not [string]::IsNullOrWhiteSpace([string]$launcherSettings.weather)) {
    [string]$launcherSettings.weather
} else { '3_clear' }
Assert-SafeContentId $weather 'weather ID'
if (-not (Test-Path -LiteralPath (Join-Path $AssettoCorsaPath "content\weather\$weather") -PathType Container)) {
    throw "Selected weather is not installed: $weather"
}
$ambientTemperature = if ($launcherSettings) { [int]$launcherSettings.ambientTemperature } else { 18 }
$roadTemperature = if ($launcherSettings) { [int]$launcherSettings.roadTemperature } else { 24 }
$sunAngle = if ($launcherSettings) { [double]$launcherSettings.sunAngle } else { 6 }
$startDelaySeconds = if ($launcherSettings) { [double]$launcherSettings.startDelaySeconds } else { 5 }
$loopDelaySeconds = if ($launcherSettings) { [double]$launcherSettings.loopDelaySeconds } else { 3 }
$loopEnabled = if ($launcherSettings) { [bool]$launcherSettings.loop } else { $true }
$tcpPort = if ($launcherSettings) { [int]$launcherSettings.tcpPort } else { 9600 }
$httpPort = if ($launcherSettings) { [int]$launcherSettings.httpPort } else { 8081 }
if ($ambientTemperature -lt -20 -or $ambientTemperature -gt 50) { throw 'Ambient temperature must be between -20 and 50 C' }
if ($roadTemperature -lt -20 -or $roadTemperature -gt 80) { throw 'Road temperature must be between -20 and 80 C' }
if ($sunAngle -lt -80 -or $sunAngle -gt 80) { throw 'Sun angle must be between -80 and 80 degrees' }
if ($startDelaySeconds -lt 0 -or $startDelaySeconds -gt 60 -or $loopDelaySeconds -lt 0 -or $loopDelaySeconds -gt 60) {
    throw 'Playback delays must be between 0 and 60 seconds'
}
if ($tcpPort -lt 1024 -or $tcpPort -gt 65535 -or $httpPort -lt 1024 -or $httpPort -gt 65535 -or $tcpPort -eq $httpPort) {
    throw 'TCP and HTTP ports must be distinct values between 1024 and 65535'
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
NAME=$serverName
CONFIG_TRACK=$($run.layout)
TRACK=$($run.track)
SUN_ANGLE=$($sunAngle.ToString([System.Globalization.CultureInfo]::InvariantCulture))
PASSWORD=
ADMIN_PASSWORD=
UDP_PORT=$tcpPort
TCP_PORT=$tcpPort
HTTP_PORT=$httpPort
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
GRAPHICS=$weather
BASE_TEMPERATURE_AMBIENT=$ambientTemperature
BASE_TEMPERATURE_ROAD=$roadTemperature
VARIATION_AMBIENT=0
VARIATION_ROAD=0
WIND_BASE_SPEED_MIN=0
WIND_BASE_SPEED_MAX=0
WIND_BASE_DIRECTION=0
WIND_VARIATION_DIRECTION=0
"@

$entryList = @"
[CAR_0]
MODEL=$playerCar
SKIN=$playerSkin
GUID=

[CAR_1]
MODEL=$($run.car)
SKIN=$($leaderSkin.Name)
GUID=1
"@

$escapedRunFile = $RunFile.Replace("'", "''")
$runDirectory = Split-Path -Parent $RunFile
$escapedRunDirectory = $runDirectory.Replace("'", "''")
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
RunDirectory: '$escapedRunDirectory'
AutoStart: true
StartDelaySeconds: $($startDelaySeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))
Loop: $($loopEnabled.ToString().ToLowerInvariant())
LoopDelaySeconds: $($loopDelaySeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))
LegacyGraphicsOffsetX: $($graphicsOffset[0].ToString([System.Globalization.CultureInfo]::InvariantCulture))
LegacyGraphicsOffsetY: $($graphicsOffset[1].ToString([System.Globalization.CultureInfo]::InvariantCulture))
LegacyGraphicsOffsetZ: $($graphicsOffset[2].ToString([System.Globalization.CultureInfo]::InvariantCulture))
"@

Write-Utf8NoBom (Join-Path $cfgPath 'server_cfg.ini') $serverCfg
Write-Utf8NoBom (Join-Path $cfgPath 'entry_list.ini') $entryList
Write-Utf8NoBom (Join-Path $cfgPath 'extra_cfg.yml') $extraCfg
Write-Utf8NoBom (Join-Path $cfgPath 'plugin_random_lead_server_cfg.yml') $pluginCfg

$runtimeInfo = [ordered]@{
    generatedAt = [DateTime]::UtcNow.ToString('o')
    runFile = $RunFile
    runDirectory = $runDirectory
    runId = [string]$run.id
    duration = [double]$run.duration
    track = [string]$run.track
    layout = [string]$run.layout
    car = [string]$run.car
    leaderSkin = $leaderSkin.Name
    playerCar = $playerCar
    playerSkin = $playerSkin
    weather = $weather
    ambientTemperature = $ambientTemperature
    roadTemperature = $roadTemperature
    sunAngle = $sunAngle
    legacyGraphicsOffset = $graphicsOffset
    address = "127.0.0.1:$tcpPort"
    httpPort = $httpPort
    logs = (Join-Path $RuntimePath 'logs')
}
Write-Utf8NoBom (Join-Path $RuntimePath 'runtime-info.json') ($runtimeInfo | ConvertTo-Json)

Write-Output "Localhost fixture prepared: $RuntimePath"
Write-Output "Run: $($run.id) ($([Math]::Round([double]$run.duration, 2)) s)"
Write-Output "Content: $($run.track) / $($run.layout) / $($run.car)"
Write-Output "Connect address: 127.0.0.1:$tcpPort"
Write-Output "Logs: $(Join-Path $RuntimePath 'logs')"
