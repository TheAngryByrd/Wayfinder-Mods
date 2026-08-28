[CmdletBinding()]
param(
    [string[]] $Path = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryDirectory = Split-Path $PSScriptRoot -Parent
if ($Path.Count -eq 0) {
    $markdownFiles = [System.Collections.Generic.List[string]]::new()
    $markdownFiles.Add((Join-Path $repositoryDirectory 'README.md'))

    $modsDirectory = Join-Path $repositoryDirectory 'src\mods'
    if (Test-Path -LiteralPath $modsDirectory) {
        foreach ($modDirectory in (Get-ChildItem -LiteralPath $modsDirectory -Directory)) {
            $modReadmes = @(
                (Join-Path $modDirectory.FullName 'README.md'),
                (Join-Path $modDirectory.FullName 'native\README.md')
            )
            foreach ($readme in $modReadmes) {
                if (Test-Path -LiteralPath $readme) {
                    $markdownFiles.Add($readme)
                }
            }
        }
    }

    $Path = @($markdownFiles | Sort-Object -Unique)
}

function Get-MarkdownAnchor {
    param([Parameter(Mandatory)][string] $Heading)

    $anchor = $Heading.ToLowerInvariant()
    $anchor = [regex]::Replace($anchor, '<[^>]+>', '')
    $anchor = [regex]::Replace($anchor, '\[([^\]]+)\]\([^\)]+\)', '$1')
    $anchor = [regex]::Replace($anchor, '[^\p{L}\p{Nd} _-]', '')
    $anchor = [regex]::Replace($anchor, '[ _]+', '-')
    return $anchor.Trim('-')
}

foreach ($markdownPath in $Path) {
    $resolvedPath = (Resolve-Path -LiteralPath $markdownPath).Path
    $content = [System.IO.File]::ReadAllText(
        $resolvedPath,
        [System.Text.UTF8Encoding]::new($false, $true)
    )
    $startMarker = '<!-- toc:start -->'
    $endMarker = '<!-- toc:end -->'
    $startIndex = $content.IndexOf($startMarker, [System.StringComparison]::Ordinal)
    $endIndex = $content.IndexOf($endMarker, [System.StringComparison]::Ordinal)

    if ($startIndex -lt 0 -or $endIndex -le $startIndex) {
        throw "TOC markers were not found in $resolvedPath"
    }

    $entries = [System.Collections.Generic.List[string]]::new()
    $inCodeBlock = $false
    foreach ($line in ($content -split "`r?`n")) {
        if ($line -match '^\s*```') {
            $inCodeBlock = -not $inCodeBlock
            continue
        }
        if ($inCodeBlock -or $line -notmatch '^(#{2,6})\s+(.+?)\s*$') {
            continue
        }

        $level = $Matches[1].Length
        $heading = $Matches[2]
        if ($heading -eq 'Contents') {
            continue
        }

        $indent = '  ' * ($level - 2)
        $anchor = Get-MarkdownAnchor -Heading $heading
        $entries.Add("$indent- [$heading](#$anchor)")
    }

    $before = $content.Substring(0, $startIndex + $startMarker.Length)
    $after = $content.Substring($endIndex)
    $updated = $before + "`r`n" + ($entries -join "`r`n") + "`r`n" + $after
    [System.IO.File]::WriteAllText($resolvedPath, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated table of contents: $resolvedPath"
}
