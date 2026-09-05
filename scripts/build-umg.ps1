[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ProjectPath,
    [Parameter(Mandatory)][string] $BuildDirectory,
    [Parameter(Mandatory)][string] $PakName,
    [Parameter(Mandatory)][string] $AssetRoot,
    [string[]] $RequiredAssets = @(),
    [string] $UnrealRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

function Get-RelativePath {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $BasePath
    )

    $baseUri = [Uri]::new([System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\')
    $pathUri = [Uri]::new([System.IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Test-UnrealRoot {
    param([Parameter(Mandatory)][string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    $editor = Join-Path $Path 'Engine\Binaries\Win64\UE4Editor-Cmd.exe'
    $unrealPak = Join-Path $Path 'Engine\Binaries\Win64\UnrealPak.exe'
    $versionFile = Join-Path $Path 'Engine\Build\Build.version'
    if (-not (Test-Path -LiteralPath $editor) -or -not (Test-Path -LiteralPath $unrealPak)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $versionFile)) {
        return $false
    }
    try {
        $version = Get-Content -LiteralPath $versionFile -Raw | ConvertFrom-Json
        return $version.MajorVersion -eq 4 -and $version.MinorVersion -eq 27
    }
    catch {
        return $false
    }
}

function Find-UnrealRoot {
    param([string] $RequestedRoot)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $candidates.Add($RequestedRoot)
    }

    $configuredRoot = [Environment]::GetEnvironmentVariable('WAYFINDER_UE427_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($configuredRoot)) {
        $candidates.Add($configuredRoot)
    }

    $installedKey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\EpicGames\Unreal Engine\4.27'
    $installed = Get-ItemProperty -LiteralPath $installedKey -ErrorAction SilentlyContinue
    $installedDirectoryProperty = if ($null -ne $installed) { $installed.PSObject.Properties['InstalledDirectory'] } else { $null }
    if ($null -ne $installedDirectoryProperty -and -not [string]::IsNullOrWhiteSpace($installedDirectoryProperty.Value)) {
        $candidates.Add($installedDirectoryProperty.Value)
    }

    $buildsKey = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Epic Games\Unreal Engine\Builds'
    $builds = Get-ItemProperty -LiteralPath $buildsKey -ErrorAction SilentlyContinue
    if ($null -ne $builds) {
        foreach ($property in $builds.PSObject.Properties) {
            if ($property.Name.StartsWith('PS', [System.StringComparison]::Ordinal) -or $property.Value -isnot [string]) {
                continue
            }
            $candidates.Add($property.Value)
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-UnrealRoot -Path $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'Unreal Engine 4.27 was not found. Set WAYFINDER_UE427_ROOT or pass -UnrealRoot.'
}

if ([System.IO.Path]::GetFileName($PakName) -ne $PakName -or -not $PakName.EndsWith('.pak', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "PakName must be a Pak file name without a directory: $PakName"
}
if ($AssetRoot -notmatch '^/Game/Mods/[A-Za-z][A-Za-z0-9_/-]*$' -or $AssetRoot.Contains('..')) {
    throw "AssetRoot must be below /Game/Mods: $AssetRoot"
}

$resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not $resolvedProjectPath.EndsWith('.uproject', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The UMG project must use the .uproject extension: $resolvedProjectPath"
}
if ([System.IO.Path]::GetFileNameWithoutExtension($resolvedProjectPath) -ne 'Atlas') {
    throw "The UMG project file must be named Atlas.uproject: $resolvedProjectPath"
}

$projectSourceDirectory = Split-Path $resolvedProjectPath -Parent
$resolvedBuildDirectory = [System.IO.Path]::GetFullPath($BuildDirectory)
if ([System.IO.Path]::GetPathRoot($resolvedBuildDirectory).TrimEnd('\') -eq $resolvedBuildDirectory.TrimEnd('\')) {
    throw "BuildDirectory cannot be a drive root: $resolvedBuildDirectory"
}

$assetRelativePath = 'Content\' + $AssetRoot.Substring('/Game/'.Length).Replace('/', '\')
$sourceAssetDirectory = Join-Path $projectSourceDirectory $assetRelativePath
if (-not (Test-Path -LiteralPath $sourceAssetDirectory)) {
    throw "The UMG asset directory was not found: $sourceAssetDirectory"
}

$resolvedUnrealRoot = Find-UnrealRoot -RequestedRoot $UnrealRoot
$editor = Join-Path $resolvedUnrealRoot 'Engine\Binaries\Win64\UE4Editor-Cmd.exe'
$unrealPak = Join-Path $resolvedUnrealRoot 'Engine\Binaries\Win64\UnrealPak.exe'

$projectBuildDirectory = Join-Path $resolvedBuildDirectory 'project'
Assert-ChildPath -Path $projectBuildDirectory -Parent $resolvedBuildDirectory -Label 'Staged UMG project'
if (Test-Path -LiteralPath $projectBuildDirectory) {
    Remove-Item -LiteralPath $projectBuildDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $projectBuildDirectory -Force | Out-Null

$stagedProjectPath = Join-Path $projectBuildDirectory 'Atlas.uproject'
Copy-Item -LiteralPath $resolvedProjectPath -Destination $stagedProjectPath -Force
foreach ($directoryName in @('Config', 'Content', 'Plugins')) {
    $sourceDirectory = Join-Path $projectSourceDirectory $directoryName
    if (Test-Path -LiteralPath $sourceDirectory) {
        Copy-Item -LiteralPath $sourceDirectory -Destination $projectBuildDirectory -Recurse -Force
    }
}

$assetGenerator = Join-Path $projectBuildDirectory 'Content\Python\generate_loadouts_assets.py'
if (Test-Path -LiteralPath $assetGenerator) {
    $generatorArguments = @(
        $stagedProjectPath,
        '-run=pythonscript',
        "-script=$assetGenerator",
        '-unattended',
        '-nop4',
        '-UTF8Output'
    )
    & $editor @generatorArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The UMG asset generator failed with exit code $LASTEXITCODE."
    }
}

$stagedAssetDirectory = Join-Path $projectBuildDirectory $assetRelativePath
foreach ($requiredAsset in $RequiredAssets) {
    if ([string]::IsNullOrWhiteSpace($requiredAsset) -or [System.IO.Path]::IsPathRooted($requiredAsset) -or $requiredAsset.Contains('..')) {
        throw "A required UMG asset path is invalid: $requiredAsset"
    }
    $requiredSourcePath = Join-Path $stagedAssetDirectory $requiredAsset
    Assert-ChildPath -Path $requiredSourcePath -Parent $stagedAssetDirectory -Label 'Required UMG asset'
    if (-not (Test-Path -LiteralPath $requiredSourcePath)) {
        throw "A required UMG asset was not found after generation: $requiredSourcePath"
    }
}

$editorArguments = @(
    $stagedProjectPath,
    '-run=cook',
    '-targetplatform=WindowsNoEditor',
    '-CookAll',
    '-compressed',
    '-unattended',
    '-nop4',
    '-UTF8Output'
)
& $editor @editorArguments
if ($LASTEXITCODE -ne 0) {
    throw "The Unreal Engine cook failed with exit code $LASTEXITCODE."
}

$cookedAssetDirectory = Join-Path $projectBuildDirectory "Saved\Cooked\WindowsNoEditor\Atlas\$assetRelativePath"
if (-not (Test-Path -LiteralPath $cookedAssetDirectory)) {
    throw "The cooked UMG asset directory was not found: $cookedAssetDirectory"
}

$allowedExtensions = @('.uasset', '.uexp', '.ubulk', '.uptnl', '.umap')
$cookedFiles = @(
    Get-ChildItem -LiteralPath $cookedAssetDirectory -File -Recurse |
        Where-Object { $_.Extension.ToLowerInvariant() -in $allowedExtensions } |
        Sort-Object FullName
)
if ($cookedFiles.Count -eq 0) {
    throw "The Unreal Engine cook produced no UMG assets: $cookedAssetDirectory"
}

foreach ($requiredAsset in $RequiredAssets) {
    $requiredCookedPath = Join-Path $cookedAssetDirectory $requiredAsset
    if (-not (Test-Path -LiteralPath $requiredCookedPath)) {
        throw "A required cooked UMG asset was not found: $requiredCookedPath"
    }
}

$pakDirectory = Join-Path $resolvedBuildDirectory 'pak'
Assert-ChildPath -Path $pakDirectory -Parent $resolvedBuildDirectory -Label 'Pak output directory'
New-Item -ItemType Directory -Path $pakDirectory -Force | Out-Null
$pakPath = Join-Path $pakDirectory $PakName
$pakBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PakName)
$responsePath = Join-Path $pakDirectory "$pakBaseName.response.txt"
$listingPath = Join-Path $pakDirectory "$pakBaseName.list.txt"
$hashPath = "$pakPath.sha256"

foreach ($outputPath in @($pakPath, $responsePath, $listingPath, $hashPath)) {
    Assert-ChildPath -Path $outputPath -Parent $pakDirectory -Label 'Pak output'
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }
}

$targetRoot = '../../../Atlas/Content/' + $AssetRoot.Substring('/Game/'.Length)
$responseLines = [System.Collections.Generic.List[string]]::new()
$expectedTargets = [System.Collections.Generic.List[string]]::new()
foreach ($cookedFile in $cookedFiles) {
    $relativePath = (Get-RelativePath -Path $cookedFile.FullName -BasePath $cookedAssetDirectory).Replace('\', '/')
    $sourcePath = $cookedFile.FullName.Replace('\', '/')
    $targetPath = "$targetRoot/$relativePath"
    $responseLines.Add(('"{0}" "{1}" -compress' -f $sourcePath, $targetPath))
    $expectedTargets.Add($targetPath)
}
[System.IO.File]::WriteAllLines($responsePath, $responseLines, [System.Text.UTF8Encoding]::new($false))

& $unrealPak $pakPath "-Create=$responsePath"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pakPath)) {
    throw "UnrealPak failed to create $pakPath."
}

$listing = @(& $unrealPak $pakPath '-List' 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "UnrealPak could not list $pakPath."
}
$listingText = $listing -join "`n"
[System.IO.File]::WriteAllText($listingPath, $listingText, [System.Text.UTF8Encoding]::new($false))

$mountMatch = [regex]::Match($listingText, '(?m)^LogPakFile: Display: Mount point (.+)$')
$expectedMount = $targetRoot.TrimEnd('/') + '/'
if (-not $mountMatch.Success -or -not $mountMatch.Groups[1].Value.Trim().Equals($expectedMount, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The Pak mount point is invalid. Expected: $expectedMount"
}

$listedPaths = @(
    [regex]::Matches($listingText, '(?m)^LogPakFile: Display: "([^"]+)" offset:') |
        ForEach-Object { $_.Groups[1].Value.Replace('\', '/') }
)
foreach ($targetPath in $expectedTargets) {
    $relativeTarget = $targetPath.Substring($expectedMount.Length)
    if ($relativeTarget -notin $listedPaths) {
        throw "The Pak listing does not contain an expected asset: $targetPath"
    }
}
foreach ($listedPath in $listedPaths) {
    if ([System.IO.Path]::IsPathRooted($listedPath) -or $listedPath.Contains('..')) {
        throw "The Pak contains an invalid relative path: $listedPath"
    }
    foreach ($forbiddenValue in @('.dll', '.exe')) {
        if ($listedPath.EndsWith($forbiddenValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The Pak contains a forbidden file type: $listedPath"
        }
    }
}

$hash = Get-FileHash -LiteralPath $pakPath -Algorithm SHA256
[System.IO.File]::WriteAllText($hashPath, $hash.Hash + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "UMG Pak: $pakPath"
Write-Host "UMG Pak SHA-256: $($hash.Hash)"
Write-Output $pakPath
