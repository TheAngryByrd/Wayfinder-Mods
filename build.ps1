[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string] $Configuration = 'Release',

    [Alias('Mods')]
    [string[]] $Mod = @(),

    [switch] $SkipNativeBuild,

    [switch] $NoArchive,

    [switch] $ListMods
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RequiredString {
    param(
        [Parameter(Mandatory)][object] $Data,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $ManifestPath
    )

    $property = $Data.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($property.Value)) {
        throw "The manifest requires a nonempty string property '$Name': $ManifestPath"
    }
    return $property.Value
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Parent,
        [Parameter(Mandatory)][string] $Label
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (-not $resolvedPath.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label is outside its required directory: $resolvedPath"
    }
}

$repositoryDirectory = $PSScriptRoot
$modsDirectory = Join-Path $repositoryDirectory 'src\mods'
$sharedSignature = Join-Path $repositoryDirectory 'src\shared\UE4SS_Signatures\GUObjectArray.lua'
$nexusDirectory = Join-Path $repositoryDirectory 'dist\NexusMods'
$archiveDirectory = Join-Path $repositoryDirectory 'dist'
$nativeBuildRoot = Join-Path $repositoryDirectory 'build\native'
$nativeBuildScript = Join-Path $repositoryDirectory 'scripts\build-native.ps1'

if (-not (Test-Path -LiteralPath $modsDirectory)) {
    throw "The mod source directory was not found: $modsDirectory"
}

$definitions = [System.Collections.Generic.List[object]]::new()
$modDirectories = @(Get-ChildItem -LiteralPath $modsDirectory -Directory | Sort-Object Name)
foreach ($modDirectory in $modDirectories) {
    $manifestPath = Join-Path $modDirectory.FullName 'mod.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "The mod directory does not contain mod.json: $($modDirectory.FullName)"
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "The mod manifest is not valid JSON: $manifestPath`n$($_.Exception.Message)"
    }

    $allowedManifestProperties = @('$schema', 'id', 'displayName', 'archiveName', 'includeWayfinderSignature', 'native')
    $unknownManifestProperties = @($manifest.PSObject.Properties.Name | Where-Object { $_ -notin $allowedManifestProperties })
    if ($unknownManifestProperties.Count -gt 0) {
        throw "The manifest contains unsupported properties: $(($unknownManifestProperties | Sort-Object) -join ', ')"
    }

    $id = Get-RequiredString -Data $manifest -Name 'id' -ManifestPath $manifestPath
    $displayName = Get-RequiredString -Data $manifest -Name 'displayName' -ManifestPath $manifestPath
    $archiveName = Get-RequiredString -Data $manifest -Name 'archiveName' -ManifestPath $manifestPath

    if ($id -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
        throw "The manifest id contains unsupported characters: $id"
    }
    if (-not $modDirectory.Name.Equals($id, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The manifest id '$id' does not match its directory '$($modDirectory.Name)'."
    }
    if ([System.IO.Path]::GetFileName($archiveName) -ne $archiveName -or -not $archiveName.EndsWith('.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The manifest archiveName must be a ZIP file name without a directory: $archiveName"
    }

    $signatureProperty = $manifest.PSObject.Properties['includeWayfinderSignature']
    if ($null -eq $signatureProperty -or $signatureProperty.Value -isnot [bool]) {
        throw "The manifest requires a Boolean property 'includeWayfinderSignature': $manifestPath"
    }

    $nativeTarget = $null
    $nativeProperty = $manifest.PSObject.Properties['native']
    if ($null -ne $nativeProperty -and $null -ne $nativeProperty.Value) {
        $unknownNativeProperties = @($nativeProperty.Value.PSObject.Properties.Name | Where-Object { $_ -ne 'target' })
        if ($unknownNativeProperties.Count -gt 0) {
            throw "The native manifest contains unsupported properties: $(($unknownNativeProperties | Sort-Object) -join ', ')"
        }
        $nativeTarget = Get-RequiredString -Data $nativeProperty.Value -Name 'target' -ManifestPath $manifestPath
        if ($nativeTarget -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
            throw "The native target contains unsupported characters: $nativeTarget"
        }
    }

    $definitions.Add([pscustomobject]@{
        Id = $id
        DisplayName = $displayName
        ArchiveName = $archiveName
        IncludeWayfinderSignature = $signatureProperty.Value
        NativeTarget = $nativeTarget
        SourceDirectory = $modDirectory.FullName
        ContentDirectory = Join-Path $modDirectory.FullName 'content'
        NativeDirectory = Join-Path $modDirectory.FullName 'native'
        SourceReadme = Join-Path $modDirectory.FullName 'README.md'
        ManifestPath = $manifestPath
    })
}

if ($definitions.Count -eq 0) {
    throw "No mod manifests were found under $modsDirectory"
}

$duplicateIds = @($definitions | Group-Object Id | Where-Object Count -gt 1)
if ($duplicateIds.Count -gt 0) {
    throw "Duplicate mod ids were found: $(($duplicateIds.Name | Sort-Object) -join ', ')"
}
$duplicateArchives = @($definitions | Group-Object ArchiveName | Where-Object Count -gt 1)
if ($duplicateArchives.Count -gt 0) {
    throw "Duplicate archive names were found: $(($duplicateArchives.Name | Sort-Object) -join ', ')"
}

if ($ListMods) {
    $definitions | Select-Object Id, DisplayName, ArchiveName, NativeTarget | Format-Table -AutoSize
    return
}

$selectedDefinitions = [System.Collections.Generic.List[object]]::new()
if ($Mod.Count -eq 0) {
    foreach ($definition in $definitions) {
        $selectedDefinitions.Add($definition)
    }
}
else {
    foreach ($requestedId in $Mod) {
        $matches = @($definitions | Where-Object { $_.Id.Equals($requestedId, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($matches.Count -eq 0) {
            throw "Unknown mod '$requestedId'. Available mods: $(($definitions.Id | Sort-Object) -join ', ')"
        }
        $alreadySelected = @($selectedDefinitions | Where-Object {
            $_.Id.Equals($matches[0].Id, [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        if (-not $alreadySelected) {
            $selectedDefinitions.Add($matches[0])
        }
    }
}

& (Join-Path $repositoryDirectory 'scripts\update-toc.ps1')

foreach ($definition in $selectedDefinitions) {
    Write-Host "Building mod: $($definition.DisplayName) [$($definition.Id)]"

    if (-not (Test-Path -LiteralPath $definition.ContentDirectory)) {
        throw "The mod content directory was not found: $($definition.ContentDirectory)"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $definition.ContentDirectory 'enabled.txt'))) {
        throw "The mod content does not contain enabled.txt: $($definition.ContentDirectory)"
    }
    if (-not (Test-Path -LiteralPath $definition.SourceReadme)) {
        throw "The mod README was not found: $($definition.SourceReadme)"
    }

    $nativeDll = $null
    if ($null -ne $definition.NativeTarget) {
        if (-not (Test-Path -LiteralPath (Join-Path $definition.NativeDirectory 'CMakeLists.txt'))) {
            throw "The native project was not found: $($definition.NativeDirectory)"
        }

        $nativeBuildDirectory = Join-Path $nativeBuildRoot $definition.Id
        $nativeDll = Join-Path $nativeBuildDirectory "$Configuration\$($definition.NativeTarget).dll"
        if (-not $SkipNativeBuild) {
            & $nativeBuildScript `
                -SourceDirectory $definition.NativeDirectory `
                -BuildDirectory $nativeBuildDirectory `
                -Target $definition.NativeTarget `
                -Configuration $Configuration
        }
        if (-not (Test-Path -LiteralPath $nativeDll)) {
            throw "The compiled DLL was not found: $nativeDll"
        }
    }

    $distributionDirectory = Join-Path $nexusDirectory $definition.Id
    Assert-ChildPath -Path $distributionDirectory -Parent $nexusDirectory -Label 'Distribution directory'
    if (Test-Path -LiteralPath $distributionDirectory) {
        Remove-Item -LiteralPath $distributionDirectory -Recurse -Force
    }

    $modOutputDirectory = Join-Path $distributionDirectory "Atlas\Binaries\Win64\Mods\$($definition.Id)"
    New-Item -ItemType Directory -Path $modOutputDirectory -Force | Out-Null

    foreach ($item in (Get-ChildItem -LiteralPath $definition.ContentDirectory -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $modOutputDirectory -Recurse -Force
    }

    if ($null -ne $nativeDll) {
        $dllDirectory = Join-Path $modOutputDirectory 'dlls'
        New-Item -ItemType Directory -Path $dllDirectory -Force | Out-Null
        Copy-Item -LiteralPath $nativeDll -Destination (Join-Path $dllDirectory 'main.dll') -Force
    }

    if ($definition.IncludeWayfinderSignature) {
        if (-not (Test-Path -LiteralPath $sharedSignature)) {
            throw "The Wayfinder UE4SS signature was not found: $sharedSignature"
        }
        $signatureOutputDirectory = Join-Path $distributionDirectory 'Atlas\Binaries\Win64\UE4SS_Signatures'
        New-Item -ItemType Directory -Path $signatureOutputDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sharedSignature -Destination $signatureOutputDirectory -Force
    }

    Copy-Item -LiteralPath $definition.SourceReadme -Destination (Join-Path $distributionDirectory 'README.md') -Force

    $archivePath = Join-Path $archiveDirectory $definition.ArchiveName
    Assert-ChildPath -Path $archivePath -Parent $archiveDirectory -Label 'Archive path'
    if (-not $NoArchive) {
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force
        }
        $archiveItems = @(
            (Join-Path $distributionDirectory 'Atlas'),
            (Join-Path $distributionDirectory 'README.md')
        )
        Compress-Archive -LiteralPath $archiveItems -DestinationPath $archivePath -CompressionLevel Optimal
    }

    Write-Host "Nexus Mods distribution: $distributionDirectory"
    if ($null -ne $nativeDll) {
        $hash = Get-FileHash -LiteralPath (Join-Path $modOutputDirectory 'dlls\main.dll') -Algorithm SHA256
        Write-Host "Packaged DLL SHA-256: $($hash.Hash)"
    }
    if (-not $NoArchive) {
        Write-Host "Nexus Mods archive: $archivePath"
    }
}
