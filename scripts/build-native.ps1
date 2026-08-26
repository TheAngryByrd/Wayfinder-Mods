[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SourceDirectory,

    [Parameter(Mandatory)]
    [string] $BuildDirectory,

    [Parameter(Mandatory)]
    [string] $Target,

    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string] $Configuration = 'Release'
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

$resolvedSource = [System.IO.Path]::GetFullPath($SourceDirectory)
$resolvedBuild = [System.IO.Path]::GetFullPath($BuildDirectory)
if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource 'CMakeLists.txt'))) {
    throw "The native source does not contain CMakeLists.txt: $resolvedSource"
}

$cmake = Find-CMake
Write-Host "CMake: $cmake"
Write-Host "Native source: $resolvedSource"
Write-Host "Native build: $resolvedBuild"
Write-Host "Target: $Target"
Write-Host "Configuration: $Configuration"

& $cmake -S $resolvedSource -B $resolvedBuild -G 'Visual Studio 17 2022' -A x64
if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed with exit code $LASTEXITCODE."
}

& $cmake --build $resolvedBuild --config $Configuration --target $Target
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

$outputDll = Join-Path $resolvedBuild "$Configuration\$Target.dll"
if (-not (Test-Path -LiteralPath $outputDll)) {
    throw "The native build did not create the expected DLL: $outputDll"
}

$hash = Get-FileHash -LiteralPath $outputDll -Algorithm SHA256
Write-Host "Native build complete: $outputDll"
Write-Host "Native DLL SHA-256: $($hash.Hash)"
