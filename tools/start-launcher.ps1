param(
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$project = Join-Path $repoRoot 'launcher\RandomLeadLauncher.csproj'
$arguments = @('run', '--project', $project, '-c', 'Release')
if ($NoBrowser) { $arguments += @('--', '--no-browser') }

Write-Output 'Starting AC Random Lead Runs Launcher at http://127.0.0.1:32123'
Write-Output 'Keep this window open while using the launcher. Ctrl+C stops the launcher and its server.'
dotnet @arguments
