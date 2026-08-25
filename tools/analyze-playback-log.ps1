param(
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$culture = [System.Globalization.CultureInfo]::InvariantCulture

if (-not $Path) {
    $logRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Assetto Corsa\ac-random-lead-runs\logs'
    $latest = Get-ChildItem -LiteralPath $logRoot -Filter 'playback-*.csv' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw "No playback diagnostics found in: $logRoot"
    }
    $Path = $latest.FullName
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Playback diagnostics file does not exist: $Path"
}

$rows = @(Import-Csv -LiteralPath $Path)
if ($rows.Count -eq 0) {
    throw "Playback diagnostics file has no samples: $Path"
}

function Convert-Number([object]$Value) {
    return [double]::Parse([string]$Value, $culture)
}

function Get-Stats([double[]]$Values) {
    $sorted = @($Values | Sort-Object)
    $p95Index = [Math]::Min([int][Math]::Floor(($sorted.Count - 1) * 0.95), $sorted.Count - 1)
    return [PSCustomObject]@{
        Mean = ($Values | Measure-Object -Average).Average
        P95  = $sorted[$p95Index]
        Max  = ($Values | Measure-Object -Maximum).Maximum
    }
}

$positionError = @($rows | ForEach-Object { Convert-Number $_.position_error_m })
$steerError = @($rows | ForEach-Object {
    [Math]::Abs((Convert-Number $_.steer_target_deg) - (Convert-Number $_.steer_actual_deg))
})
$wheelError = @($rows | ForEach-Object {
    [Math]::Abs((Convert-Number $_.wheel_fl_target_rad_s) - (Convert-Number $_.wheel_fl_actual_rad_s))
})
$rpmError = @($rows | ForEach-Object {
    [Math]::Abs((Convert-Number $_.rpm_target) - (Convert-Number $_.rpm_actual))
})

$positionStats = Get-Stats $positionError
$steerStats = Get-Stats $steerError
$wheelStats = Get-Stats $wheelError
$rpmStats = Get-Stats $rpmError

[PSCustomObject]@{
    Path                       = (Resolve-Path -LiteralPath $Path).Path
    Samples                    = $rows.Count
    DurationSeconds            = Convert-Number $rows[-1].time_s
    HeightOffsetCm             = (Convert-Number $rows[-1].height_offset_m) * 100
    PositionErrorMeanCm        = $positionStats.Mean * 100
    PositionErrorP95Cm         = $positionStats.P95 * 100
    PositionErrorMaxCm         = $positionStats.Max * 100
    SteerErrorMeanDeg          = $steerStats.Mean
    SteerErrorP95Deg           = $steerStats.P95
    WheelFLErrorMeanRadS       = $wheelStats.Mean
    WheelFLErrorP95RadS        = $wheelStats.P95
    RPMErrorMean               = $rpmStats.Mean
    RPMErrorP95                = $rpmStats.P95
    RideHeightFrontMeanMm      = (@($rows | ForEach-Object { Convert-Number $_.ride_height_front_m }) | Measure-Object -Average).Average * 1000
    RideHeightRearMeanMm       = (@($rows | ForEach-Object { Convert-Number $_.ride_height_rear_m }) | Measure-Object -Average).Average * 1000
    GroundDistanceMeanMm       = (@($rows | ForEach-Object { Convert-Number $_.ground_distance_m }) | Measure-Object -Average).Average * 1000
    SuspensionFrontLeftMeanMm  = (@($rows | ForEach-Object { Convert-Number $_.suspension_fl_m }) | Measure-Object -Average).Average * 1000
    SuspensionFrontRightMeanMm = (@($rows | ForEach-Object { Convert-Number $_.suspension_fr_m }) | Measure-Object -Average).Average * 1000
    AudioStatus                = (@($rows.audio_status | Sort-Object -Unique) -join '; ')
}
