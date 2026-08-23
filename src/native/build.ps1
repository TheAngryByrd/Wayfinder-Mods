[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string] $Configuration = 'Release',

    [switch] $NoCopy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Find-CMake {
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $visualStudioRoots = @(
        'C:\Program Files\Microsoft Visual Studio\2022',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022'
    )

    foreach ($root in $visualStudioRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        $bundled = Get-ChildItem -LiteralPath $root -Recurse -Filter cmake.exe -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*CommonExtensions*Microsoft*CMake*bin*' } |
            Select-Object -First 1 -ExpandProperty FullName

        if ($bundled) {
            return $bundled
        }
    }

    throw 'CMake was not found. Install Visual Studio 2022 with Desktop development with C++, or add CMake to PATH.'
}

$cmake = Find-CMake
$sourceDirectory = $PSScriptRoot
$buildDirectory = Join-Path $sourceDirectory 'build'
$outputDll = Join-Path $buildDirectory "$Configuration\MorePlayersSteamLimit.dll"
$repositoryDirectory = Split-Path (Split-Path $sourceDirectory -Parent) -Parent
$modDll = Join-Path $repositoryDirectory 'dist\NexusMods\Atlas\Binaries\Win64\Mods\MorePlayers\dlls\main.dll'

Write-Host "CMake: $cmake"
Write-Host "Configuration: $Configuration"

& $cmake -S $sourceDirectory -B $buildDirectory -G 'Visual Studio 17 2022' -A x64
if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed with exit code $LASTEXITCODE."
}

& $cmake --build $buildDirectory --config $Configuration --target MorePlayersSteamLimit
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $outputDll)) {
    throw "Build completed but the expected DLL was not found: $outputDll"
}

if (-not $NoCopy) {
    New-Item -ItemType Directory -Path (Split-Path $modDll -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $outputDll -Destination $modDll -Force
    Write-Host "Copied compiled DLL: $modDll"
}

$hash = Get-FileHash -LiteralPath $outputDll -Algorithm SHA256
Write-Host "Build complete: $outputDll"
Write-Host "SHA-256: $($hash.Hash)"
