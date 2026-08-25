param(
    [string]$AssettoCorsaPath = 'N:\SteamLibrary\steamapps\common\assettocorsa'
)

$ErrorActionPreference = 'Stop'

$modeSource = Join-Path $PSScriptRoot '..\src\new-mode'
$appSource = Join-Path $PSScriptRoot '..\src\app'
$modeDestination = Join-Path $AssettoCorsaPath 'extension\lua\new-modes\ac-random-lead-runs-phase0'
$appDestination = Join-Path $AssettoCorsaPath 'apps\lua\ac_random_lead_runs_phase0'

if (-not (Test-Path -LiteralPath $modeSource -PathType Container)) {
    throw "Mode source folder does not exist: $modeSource"
}

if (-not (Test-Path -LiteralPath $appSource -PathType Container)) {
    throw "App source folder does not exist: $appSource"
}

if (-not (Test-Path -LiteralPath $AssettoCorsaPath -PathType Container)) {
    throw "Assetto Corsa folder does not exist: $AssettoCorsaPath"
}

New-Item -ItemType Directory -Path $modeDestination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $modeSource 'manifest.ini') -Destination $modeDestination -Force
Copy-Item -LiteralPath (Join-Path $modeSource 'mode.lua') -Destination $modeDestination -Force
Copy-Item -LiteralPath (Join-Path $modeSource 'run_store.lua') -Destination $modeDestination -Force
Copy-Item -LiteralPath (Join-Path $modeSource 'trajectory.lua') -Destination $modeDestination -Force

New-Item -ItemType Directory -Path $appDestination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $appSource 'manifest.ini') -Destination $appDestination -Force
Copy-Item -LiteralPath (Join-Path $appSource 'ac_random_lead_runs_phase0.lua') -Destination $appDestination -Force
Copy-Item -LiteralPath (Join-Path $appSource 'icon.png') -Destination $appDestination -Force

Write-Output "Installed Phase 1.5 mode to: $modeDestination"
Write-Output "Installed Phase 1.5 app to: $appDestination"
