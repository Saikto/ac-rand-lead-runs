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

function Copy-PluginWithRetry([string]$Source, [string]$Destination) {
    $lastError = $null
    for ($attempt = 1; $attempt -le 25; $attempt++) {
        try {
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
            return
        }
        catch [System.IO.IOException] {
            $lastError = $_
            if ((Test-Path -LiteralPath $Destination -PathType Leaf) -and
                (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq
                (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash) {
                Write-Output 'Plugin DLL is already current; reusing the locked copy.'
                return
            }
            if ($attempt -lt 25) { Start-Sleep -Milliseconds 200 }
        }
    }
    throw "Could not update plugin DLL after 5 seconds. A previous AssettoServer process is still using '$Destination'. Stop that server and retry. Original error: $($lastError.Exception.Message)"
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
$roadTemperatureDelta = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'roadTemperatureDelta') { [int]$launcherSettings.roadTemperatureDelta } else { 6 }
$timeOfDay = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'timeOfDay') { [string]$launcherSettings.timeOfDay } else { '13:00' }
$timeMultiplier = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'timeMultiplier') { [double]$launcherSettings.timeMultiplier } else { 1 }
$windSpeed = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'windSpeed') { [int]$launcherSettings.windSpeed } else { 0 }
$windDirection = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'windDirection') { [int]$launcherSettings.windDirection } else { 0 }
$trackGrip = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'trackGrip') { [int]$launcherSettings.trackGrip } else { 100 }
$tractionControlAllowed = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'tractionControlAllowed') { [int]$launcherSettings.tractionControlAllowed } else { 1 }
$absAllowed = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'absAllowed') { [int]$launcherSettings.absAllowed } else { 1 }
$stabilityAllowed = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'stabilityAllowed' -and [bool]$launcherSettings.stabilityAllowed) { 1 } else { 0 }
$autoClutchAllowed = if (-not $launcherSettings -or -not ($launcherSettings.PSObject.Properties.Name -contains 'autoClutchAllowed') -or [bool]$launcherSettings.autoClutchAllowed) { 1 } else { 0 }
$damageMultiplier = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'damageMultiplier') { [int]$launcherSettings.damageMultiplier } else { 0 }
$fuelRate = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'fuelRate') { [int]$launcherSettings.fuelRate } else { 0 }
$tyreWearRate = if ($launcherSettings -and $launcherSettings.PSObject.Properties.Name -contains 'tyreWearRate') { [int]$launcherSettings.tyreWearRate } else { 0 }
$tyreBlanketsAllowed = if (-not $launcherSettings -or -not ($launcherSettings.PSObject.Properties.Name -contains 'tyreBlanketsAllowed') -or [bool]$launcherSettings.tyreBlanketsAllowed) { 1 } else { 0 }
$parsedTime = [DateTime]::ParseExact($timeOfDay, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
$timeSeconds = $parsedTime.TimeOfDay.TotalSeconds
$sunAngle = 16.0 * ($timeSeconds - 46800.0) / 3600.0
$startDelaySeconds = if ($launcherSettings) { [double]$launcherSettings.startDelaySeconds } else { 5 }
$loopDelaySeconds = if ($launcherSettings) { [double]$launcherSettings.loopDelaySeconds } else { 3 }
$loopEnabled = if ($launcherSettings) { [bool]$launcherSettings.loop } else { $true }
$tcpPort = if ($launcherSettings) { [int]$launcherSettings.tcpPort } else { 9600 }
$httpPort = if ($launcherSettings) { [int]$launcherSettings.httpPort } else { 8081 }
if ($ambientTemperature -lt -20 -or $ambientTemperature -gt 50) { throw 'Ambient temperature must be between -20 and 50 C' }
if ($roadTemperatureDelta -lt -20 -or $roadTemperatureDelta -gt 40 -or ($ambientTemperature + $roadTemperatureDelta) -lt -20 -or ($ambientTemperature + $roadTemperatureDelta) -gt 80) { throw 'Road temperature delta or resulting temperature is outside the supported range' }
if ($timeSeconds -lt 28800 -or $timeSeconds -gt 64800) { throw 'Time of day must be between 08:00 and 18:00' }
if ($timeMultiplier -lt 1 -or $timeMultiplier -gt 60) { throw 'Time multiplier must be between 1 and 60' }
if ($windSpeed -lt 0 -or $windSpeed -gt 100 -or $windDirection -lt 0 -or $windDirection -gt 359) { throw 'Wind setting is outside the supported range' }
if ($trackGrip -lt 80 -or $trackGrip -gt 100) { throw 'Track grip must be between 80 and 100 percent' }
if ($tractionControlAllowed -notin @(0, 1, 2) -or $absAllowed -notin @(0, 1, 2)) { throw 'TC and ABS values must be 0, 1, or 2' }
if ($damageMultiplier -lt 0 -or $damageMultiplier -gt 200 -or $fuelRate -lt 0 -or $fuelRate -gt 200 -or $tyreWearRate -lt 0 -or $tyreWearRate -gt 200) { throw 'Damage, fuel, and tyre rates must be between 0 and 200 percent' }
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
Copy-PluginWithRetry $pluginDll (Join-Path $pluginPath 'RandomLeadServerPlugin.dll')

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
FUEL_RATE=$fuelRate
DAMAGE_MULTIPLIER=$damageMultiplier
TYRE_WEAR_RATE=$tyreWearRate
ALLOWED_TYRES_OUT=-1
ABS_ALLOWED=$absAllowed
TC_ALLOWED=$tractionControlAllowed
STABILITY_ALLOWED=$stabilityAllowed
AUTOCLUTCH_ALLOWED=$autoClutchAllowed
TYRE_BLANKETS_ALLOWED=$tyreBlanketsAllowed
FORCE_VIRTUAL_MIRROR=0
REGISTER_TO_LOBBY=0
TIME_OF_DAY_MULT=$($timeMultiplier.ToString([System.Globalization.CultureInfo]::InvariantCulture))
WELCOME_MESSAGE=

[PRACTICE]
INFINITE=1

[DYNAMIC_TRACK]
SESSION_START=$trackGrip

[WEATHER_0]
GRAPHICS=$weather
BASE_TEMPERATURE_AMBIENT=$ambientTemperature
BASE_TEMPERATURE_ROAD=$roadTemperatureDelta
VARIATION_AMBIENT=0
VARIATION_ROAD=0
WIND_BASE_SPEED_MIN=$windSpeed
WIND_BASE_SPEED_MAX=$windSpeed
WIND_BASE_DIRECTION=$windDirection
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
    roadTemperatureDelta = $roadTemperatureDelta
    roadTemperature = $ambientTemperature + $roadTemperatureDelta
    timeOfDay = $timeOfDay
    sunAngle = $sunAngle
    timeMultiplier = $timeMultiplier
    windSpeed = $windSpeed
    windDirection = $windDirection
    trackGrip = $trackGrip
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
