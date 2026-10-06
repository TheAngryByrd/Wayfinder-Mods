[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel')]
    [string] $Configuration = 'Release',

    [Alias('Mods')]
    [string[]] $Mod = @(),

    [switch] $SkipNativeBuild,

    [switch] $SkipUmgBuild,

    [string] $UnrealRoot = '',

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

# Windows PowerShell 5.1 Compress-Archive writes backslash entry names, which
# the ZIP specification does not permit and some extractors mishandle. This
# writer uses forward slashes and a sorted, repeatable entry order. The README
# entry gets a per-mod name, so two archives in one game folder do not
# overwrite each other's README.
function New-ModArchive {
    param(
        [Parameter(Mandatory)][string] $DistributionDirectory,
        [Parameter(Mandatory)][string] $ArchivePath,
        [Parameter(Mandatory)][string] $ReadmeEntryName
    )

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $root = [System.IO.Path]::GetFullPath($DistributionDirectory).TrimEnd('\') + '\'
    $entries = @(Get-ChildItem -LiteralPath (Join-Path $DistributionDirectory 'Atlas') -File -Recurse |
        ForEach-Object { [pscustomobject]@{ Source = $_.FullName; Name = $_.FullName.Substring($root.Length).Replace('\', '/') } } |
        Sort-Object -Property Name)
    $entries += [pscustomobject]@{ Source = (Join-Path $DistributionDirectory 'README.md'); Name = $ReadmeEntryName }

    $archive = [System.IO.Compression.ZipFile]::Open($ArchivePath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($entry in $entries) {
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $entry.Source, $entry.Name, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    }
    finally {
        $archive.Dispose()
    }
}

$repositoryDirectory = $PSScriptRoot
$modsDirectory = Join-Path $repositoryDirectory 'src\mods'
$sharedSignature = Join-Path $repositoryDirectory 'src\shared\UE4SS_Signatures\GUObjectArray.lua'
$nexusDirectory = Join-Path $repositoryDirectory 'dist\NexusMods'
$archiveDirectory = Join-Path $repositoryDirectory 'dist'
$nativeBuildRoot = Join-Path $repositoryDirectory 'build\native'
$umgBuildRoot = Join-Path $repositoryDirectory 'build\umg'
$nativeBuildScript = Join-Path $repositoryDirectory 'scripts\build-native.ps1'
$umgBuildScript = Join-Path $repositoryDirectory 'scripts\build-umg.ps1'

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

    $allowedManifestProperties = @('$schema', 'id', 'displayName', 'archiveName', 'includeWayfinderSignature', 'validation', 'native', 'umg')
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

    $validationScript = $null
    $validationProperty = $manifest.PSObject.Properties['validation']
    if ($null -ne $validationProperty -and $null -ne $validationProperty.Value) {
        $unknownValidationProperties = @($validationProperty.Value.PSObject.Properties.Name | Where-Object { $_ -ne 'script' })
        if ($unknownValidationProperties.Count -gt 0) {
            throw "The validation manifest contains unsupported properties: $(($unknownValidationProperties | Sort-Object) -join ', ')"
        }
        $validationScriptRelative = Get-RequiredString -Data $validationProperty.Value -Name 'script' -ManifestPath $manifestPath
        if ([System.IO.Path]::IsPathRooted($validationScriptRelative) -or $validationScriptRelative.Contains('..') -or
            -not $validationScriptRelative.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The validation script must be a relative .ps1 path: $validationScriptRelative"
        }
        $validationScript = Join-Path $modDirectory.FullName $validationScriptRelative
        Assert-ChildPath -Path $validationScript -Parent $modDirectory.FullName -Label 'Validation script'
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

    $umgProject = $null
    $umgPakName = $null
    $umgAssetRoot = $null
    $umgRequiredAssets = @()
    $umgProperty = $manifest.PSObject.Properties['umg']
    if ($null -ne $umgProperty -and $null -ne $umgProperty.Value) {
        $allowedUmgProperties = @('project', 'pakName', 'assetRoot', 'requiredAssets')
        $unknownUmgProperties = @($umgProperty.Value.PSObject.Properties.Name | Where-Object { $_ -notin $allowedUmgProperties })
        if ($unknownUmgProperties.Count -gt 0) {
            throw "The UMG manifest contains unsupported properties: $(($unknownUmgProperties | Sort-Object) -join ', ')"
        }

        $umgProjectRelative = Get-RequiredString -Data $umgProperty.Value -Name 'project' -ManifestPath $manifestPath
        if ([System.IO.Path]::IsPathRooted($umgProjectRelative) -or $umgProjectRelative.Contains('..') -or -not $umgProjectRelative.EndsWith('.uproject', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The UMG project must be a relative .uproject path: $umgProjectRelative"
        }
        $umgProject = Join-Path $modDirectory.FullName $umgProjectRelative
        Assert-ChildPath -Path $umgProject -Parent $modDirectory.FullName -Label 'UMG project'

        $umgPakName = Get-RequiredString -Data $umgProperty.Value -Name 'pakName' -ManifestPath $manifestPath
        if ([System.IO.Path]::GetFileName($umgPakName) -ne $umgPakName -or -not $umgPakName.EndsWith('.pak', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The UMG pakName must be a Pak file name without a directory: $umgPakName"
        }

        $umgAssetRoot = Get-RequiredString -Data $umgProperty.Value -Name 'assetRoot' -ManifestPath $manifestPath
        if ($umgAssetRoot -notmatch '^/Game/Mods/[A-Za-z][A-Za-z0-9_/-]*$' -or $umgAssetRoot.Contains('..')) {
            throw "The UMG assetRoot must be below /Game/Mods: $umgAssetRoot"
        }

        $requiredAssetsProperty = $umgProperty.Value.PSObject.Properties['requiredAssets']
        if ($null -eq $requiredAssetsProperty -or $requiredAssetsProperty.Value -is [string]) {
            throw "The UMG manifest requires an array property 'requiredAssets': $manifestPath"
        }
        $umgRequiredAssets = @($requiredAssetsProperty.Value)
        if ($umgRequiredAssets.Count -eq 0) {
            throw "The UMG requiredAssets array cannot be empty: $manifestPath"
        }
        foreach ($requiredAsset in $umgRequiredAssets) {
            if ($requiredAsset -isnot [string] -or [string]::IsNullOrWhiteSpace($requiredAsset) -or
                [System.IO.Path]::IsPathRooted($requiredAsset) -or $requiredAsset.Contains('..') -or
                -not $requiredAsset.EndsWith('.uasset', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "The UMG requiredAssets array contains an invalid path: $requiredAsset"
            }
        }
    }

    $definitions.Add([pscustomobject]@{
        Id = $id
        DisplayName = $displayName
        ArchiveName = $archiveName
        IncludeWayfinderSignature = $signatureProperty.Value
        ValidationScript = $validationScript
        NativeTarget = $nativeTarget
        UmgProject = $umgProject
        UmgPakName = $umgPakName
        UmgAssetRoot = $umgAssetRoot
        UmgRequiredAssets = $umgRequiredAssets
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
    $definitions | Select-Object Id, DisplayName, ArchiveName, NativeTarget, UmgPakName | Format-Table -AutoSize
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
    if ($null -ne $definition.ValidationScript) {
        if (-not (Test-Path -LiteralPath $definition.ValidationScript)) {
            throw "The mod validation script was not found: $($definition.ValidationScript)"
        }
        & $definition.ValidationScript `
            -Phase Source `
            -RepositoryDirectory $repositoryDirectory `
            -ModDirectory $definition.SourceDirectory
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

    $umgPak = $null
    if ($null -ne $definition.UmgPakName) {
        if (-not (Test-Path -LiteralPath $definition.UmgProject)) {
            throw "The UMG project was not found: $($definition.UmgProject)"
        }
        if (-not (Test-Path -LiteralPath $umgBuildScript)) {
            throw "The UMG build script was not found: $umgBuildScript"
        }

        $umgBuildDirectory = Join-Path $umgBuildRoot $definition.Id
        $umgPak = Join-Path $umgBuildDirectory "pak\$($definition.UmgPakName)"
        if (-not $SkipUmgBuild) {
            $umgArguments = @{
                ProjectPath = $definition.UmgProject
                BuildDirectory = $umgBuildDirectory
                PakName = $definition.UmgPakName
                AssetRoot = $definition.UmgAssetRoot
                RequiredAssets = $definition.UmgRequiredAssets
            }
            if (-not [string]::IsNullOrWhiteSpace($UnrealRoot)) {
                $umgArguments.UnrealRoot = $UnrealRoot
            }
            & $umgBuildScript @umgArguments | Out-Null
        }
        if (-not (Test-Path -LiteralPath $umgPak)) {
            throw "The cooked UMG Pak was not found: $umgPak"
        }
        $umgHashPath = "$umgPak.sha256"
        if (-not (Test-Path -LiteralPath $umgHashPath)) {
            throw "The verified UMG Pak hash was not found: $umgHashPath"
        }
        $expectedUmgHash = (Get-Content -LiteralPath $umgHashPath -Raw).Trim()
        if ($expectedUmgHash -notmatch '^[A-Fa-f0-9]{64}$') {
            throw "The verified UMG Pak hash is invalid: $umgHashPath"
        }
        $actualUmgHash = (Get-FileHash -LiteralPath $umgPak -Algorithm SHA256).Hash
        if (-not $actualUmgHash.Equals($expectedUmgHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The UMG Pak does not match its verified hash: $umgPak"
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

        # A statically linked library can require its license notice in each
        # binary distribution, for example MinHook's BSD license.
        $nativeLicenses = Join-Path $definition.NativeDirectory 'licenses'
        if (Test-Path -LiteralPath $nativeLicenses) {
            $licenseOutputDirectory = Join-Path $modOutputDirectory 'licenses'
            New-Item -ItemType Directory -Path $licenseOutputDirectory -Force | Out-Null
            Copy-Item -Path (Join-Path $nativeLicenses '*') -Destination $licenseOutputDirectory -Recurse -Force
        }
    }

    if ($definition.IncludeWayfinderSignature) {
        if (-not (Test-Path -LiteralPath $sharedSignature)) {
            throw "The Wayfinder UE4SS signature was not found: $sharedSignature"
        }
        $signatureOutputDirectory = Join-Path $distributionDirectory 'Atlas\Binaries\Win64\UE4SS_Signatures'
        New-Item -ItemType Directory -Path $signatureOutputDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sharedSignature -Destination $signatureOutputDirectory -Force
    }

    if ($null -ne $umgPak) {
        $logicModsDirectory = Join-Path $distributionDirectory 'Atlas\Content\Paks\LogicMods'
        New-Item -ItemType Directory -Path $logicModsDirectory -Force | Out-Null
        Copy-Item -LiteralPath $umgPak -Destination (Join-Path $logicModsDirectory $definition.UmgPakName) -Force
    }

    Copy-Item -LiteralPath $definition.SourceReadme -Destination (Join-Path $distributionDirectory 'README.md') -Force

    if ($null -ne $definition.ValidationScript) {
        & $definition.ValidationScript `
            -Phase Package `
            -RepositoryDirectory $repositoryDirectory `
            -ModDirectory $definition.SourceDirectory `
            -DistributionDirectory $distributionDirectory
    }

    $archivePath = Join-Path $archiveDirectory $definition.ArchiveName
    Assert-ChildPath -Path $archivePath -Parent $archiveDirectory -Label 'Archive path'
    if (-not $NoArchive) {
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force
        }
        New-ModArchive `
            -DistributionDirectory $distributionDirectory `
            -ArchivePath $archivePath `
            -ReadmeEntryName "$($definition.Id)-README.md"
    }

    Write-Host "Nexus Mods distribution: $distributionDirectory"
    if ($null -ne $nativeDll) {
        $hash = Get-FileHash -LiteralPath (Join-Path $modOutputDirectory 'dlls\main.dll') -Algorithm SHA256
        Write-Host "Packaged DLL SHA-256: $($hash.Hash)"
    }
    if ($null -ne $umgPak) {
        $umgHash = Get-FileHash -LiteralPath (Join-Path $distributionDirectory "Atlas\Content\Paks\LogicMods\$($definition.UmgPakName)") -Algorithm SHA256
        Write-Host "Packaged UMG Pak SHA-256: $($umgHash.Hash)"
    }
    if (-not $NoArchive) {
        Write-Host "Nexus Mods archive: $archivePath"
    }
}
