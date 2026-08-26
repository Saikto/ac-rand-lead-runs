param(
    [string]$AssettoCorsaPath = 'N:\SteamLibrary\steamapps\common\assettocorsa'
)

$ErrorActionPreference = 'Stop'
$assettoCorsaRoot = [System.IO.Path]::GetFullPath($AssettoCorsaPath)
$modeSource = Join-Path $PSScriptRoot '..\src\new-mode'
$appSource = Join-Path $PSScriptRoot '..\src\app'
$modesRoot = Join-Path $assettoCorsaRoot 'extension\lua\new-modes'
$appsRoot = Join-Path $assettoCorsaRoot 'apps\lua'
$modeDestination = Join-Path $modesRoot 'ac-random-lead-runs'
$appDestination = Join-Path $appsRoot 'ac_random_lead_runs'

function Remove-LegacyDirectory([string]$Path, [string]$ExpectedParent) {
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedParent = [System.IO.Path]::GetFullPath($ExpectedParent)
    if ([System.IO.Directory]::GetParent($resolvedPath).FullName -ne $resolvedParent) {
        throw "Refusing to remove unexpected legacy path: $resolvedPath"
    }
    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
        Write-Output "Removed legacy install: $resolvedPath"
    }
}

if (-not (Test-Path -LiteralPath $modeSource -PathType Container)) {
    throw "Mode source folder does not exist: $modeSource"
}
if (-not (Test-Path -LiteralPath $appSource -PathType Container)) {
    throw "App source folder does not exist: $appSource"
}
if (-not (Test-Path -LiteralPath $assettoCorsaRoot -PathType Container)) {
    throw "Assetto Corsa folder does not exist: $assettoCorsaRoot"
}

Remove-LegacyDirectory (Join-Path $modesRoot 'ac-random-lead-runs-phase0') $modesRoot
Remove-LegacyDirectory (Join-Path $appsRoot 'ac_random_lead_runs_phase0') $appsRoot

New-Item -ItemType Directory -Path $modeDestination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $modeSource 'manifest.ini') -Destination $modeDestination -Force
Copy-Item -LiteralPath (Join-Path $modeSource 'mode.lua') -Destination $modeDestination -Force
Copy-Item -LiteralPath (Join-Path $modeSource 'run_store.lua') -Destination $modeDestination -Force

New-Item -ItemType Directory -Path $appDestination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $appSource 'manifest.ini') -Destination $appDestination -Force
Copy-Item -LiteralPath (Join-Path $appSource 'ac_random_lead_runs.lua') -Destination $appDestination -Force
Copy-Item -LiteralPath (Join-Path $appSource 'icon.png') -Destination $appDestination -Force

Write-Output "Installed recorder mode to: $modeDestination"
Write-Output "Installed app to: $appDestination"
