param(
    [string]$AssettoServerSource = (Join-Path $PSScriptRoot '..\.tmp\AssettoServer'),
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$pinnedCommit = '6ce86addc1b1c70caf018a7b39f6d7bc9aa9493f'
$repository = 'https://github.com/compujuckel/AssettoServer.git'
$project = Join-Path $PSScriptRoot '..\server-plugin\RandomLeadServerPlugin.csproj'
$AssettoServerSource = [System.IO.Path]::GetFullPath($AssettoServerSource)
$project = [System.IO.Path]::GetFullPath($project)

if (-not (Test-Path -LiteralPath $AssettoServerSource -PathType Container)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $AssettoServerSource) -Force | Out-Null
    git clone $repository $AssettoServerSource
}

$actualCommit = (git -C $AssettoServerSource rev-parse HEAD).Trim()
if ($actualCommit -ne $pinnedCommit) {
    throw "AssettoServer source must be pinned to $pinnedCommit, found $actualCommit"
}

dotnet build $project -c $Configuration -p:AssettoServerSource=$AssettoServerSource
