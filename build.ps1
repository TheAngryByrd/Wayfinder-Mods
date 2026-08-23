[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string] $Configuration = 'Release',

    [switch] $SkipNativeBuild,

    [switch] $NoArchive
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryDirectory = $PSScriptRoot
$sourceDirectory = Join-Path $repositoryDirectory 'src'
$nativeDirectory = Join-Path $sourceDirectory 'native'
$nativeDll = Join-Path $nativeDirectory "build\$Configuration\MorePlayersSteamLimit.dll"
$distributionDirectory = Join-Path $repositoryDirectory 'dist\NexusMods'
$archivePath = Join-Path $repositoryDirectory 'dist\Wayfinder-MorePlayers-NexusMods.zip'
$modDirectory = Join-Path $distributionDirectory 'Atlas\Binaries\Win64\Mods\MorePlayers'
$signatureDirectory = Join-Path $distributionDirectory 'Atlas\Binaries\Win64\UE4SS_Signatures'

if (-not $SkipNativeBuild) {
    & (Join-Path $nativeDirectory 'build.ps1') -Configuration $Configuration -NoCopy
    if ($LASTEXITCODE -ne 0) {
        throw "Native build failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $nativeDll)) {
    throw "The compiled DLL was not found: $nativeDll"
}

$resolvedRepository = [System.IO.Path]::GetFullPath($repositoryDirectory).TrimEnd('\')
$resolvedDistribution = [System.IO.Path]::GetFullPath($distributionDirectory).TrimEnd('\')
$requiredPrefix = $resolvedRepository + '\dist\'
if (-not $resolvedDistribution.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The distribution directory is outside the repository dist directory: $resolvedDistribution"
}

if (Test-Path -LiteralPath $distributionDirectory) {
    Remove-Item -LiteralPath $distributionDirectory -Recurse -Force
}

New-Item -ItemType Directory -Path $modDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $signatureDirectory -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceDirectory 'MorePlayers\Scripts') -Destination $modDirectory -Recurse
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'MorePlayers\config.ini') -Destination $modDirectory
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'MorePlayers\enabled.txt') -Destination $modDirectory
New-Item -ItemType Directory -Path (Join-Path $modDirectory 'dlls') -Force | Out-Null
Copy-Item -LiteralPath $nativeDll -Destination (Join-Path $modDirectory 'dlls\main.dll')
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'UE4SS_Signatures\GUObjectArray.lua') -Destination $signatureDirectory
Copy-Item -LiteralPath (Join-Path $repositoryDirectory 'packaging\NexusMods\README.md') -Destination $distributionDirectory

if (-not $NoArchive) {
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -LiteralPath (Join-Path $distributionDirectory 'Atlas'),(Join-Path $distributionDirectory 'README.md') -DestinationPath $archivePath -CompressionLevel Optimal
}

$hash = Get-FileHash -LiteralPath (Join-Path $modDirectory 'dlls\main.dll') -Algorithm SHA256
Write-Host "Nexus Mods distribution: $distributionDirectory"
Write-Host "DLL SHA-256: $($hash.Hash)"
if (-not $NoArchive) {
    Write-Host "Nexus Mods archive: $archivePath"
}
