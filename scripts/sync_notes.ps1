param(
    [string]$SourceRoot = "D:\obsidian\工作"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$docsRoot = Join-Path $projectRoot "docs"
$projectsRoot = Join-Path $docsRoot "项目"
$supplementFolderName = "补充页"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
}

function Get-NavIndent {
    param([int]$Level)

    return (" " * (2 + ($Level * 4)))
}

function To-ForwardSlash {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return ($Value -replace '\\', '/')
}

function Get-StemPath {
    param([string]$RelativePath)

    $normalizedPath = To-ForwardSlash $RelativePath
    $extension = [System.IO.Path]::GetExtension($normalizedPath)

    if ([string]::IsNullOrEmpty($extension)) {
        return $normalizedPath
    }

    return $normalizedPath.Substring(0, $normalizedPath.Length - $extension.Length)
}

function Get-RelativePath {
    param(
        [string]$FromDirectory,
        [string]$ToPath
    )

    $fromFullPath = [System.IO.Path]::GetFullPath($FromDirectory)
    if (-not $fromFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fromFullPath += [System.IO.Path]::DirectorySeparatorChar
    }

    $toFullPath = [System.IO.Path]::GetFullPath($ToPath)
    $fromUri = New-Object System.Uri($fromFullPath)
    $toUri = New-Object System.Uri($toFullPath)
    $relativeUri = $fromUri.MakeRelativeUri($toUri)

    return [System.Uri]::UnescapeDataString($relativeUri.ToString())
}

function Get-OutputPathInfo {
    param([string]$ProjectRelativePath)

    $normalizedPath = To-ForwardSlash $ProjectRelativePath
    $supplementPrefix = "$supplementFolderName/"

    if ($normalizedPath.StartsWith($supplementPrefix)) {
        $navRelativePath = $normalizedPath.Substring($supplementPrefix.Length)
        return [PSCustomObject]@{
            Category         = "supplement"
            OutputRelative   = "$supplementFolderName/$navRelativePath"
            NavRelativePath  = $navRelativePath
            SectionLabel     = $supplementFolderName
        }
    }

    return [PSCustomObject]@{
        Category         = "document"
        OutputRelative   = "文档/$normalizedPath"
        NavRelativePath  = $normalizedPath
        SectionLabel     = "文档"
    }
}

function Get-ProjectMarkdownEntries {
    param([string]$ProjectSourceRoot)

    $entries = @()
    $files = Get-ChildItem -Path $ProjectSourceRoot -Recurse -File -Filter "*.md" -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $relativePath = Get-RelativePath -FromDirectory $ProjectSourceRoot -ToPath $file.FullName
        $relativePath = To-ForwardSlash $relativePath
        $outputInfo = Get-OutputPathInfo -ProjectRelativePath $relativePath

        $entries += [PSCustomObject]@{
            SourceFullName   = $file.FullName
            RelativePath     = $relativePath
            StemRelative     = Get-StemPath $relativePath
            BaseName         = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            Category         = $outputInfo.Category
            OutputRelative   = $outputInfo.OutputRelative
            NavRelativePath  = $outputInfo.NavRelativePath
        }
    }

    return $entries
}

function Resolve-WikiLinkTarget {
    param(
        [string]$TargetSpec,
        [object[]]$MarkdownEntries
    )

    if ([string]::IsNullOrWhiteSpace($TargetSpec)) {
        return $null
    }

    $target = $TargetSpec.Trim() -replace '\\', '/'
    $anchor = ""

    if ($target -match '^(.*?)(#.*)$') {
        $target = $matches[1]
        $anchor = $matches[2]
    }

    if ([string]::IsNullOrWhiteSpace($target)) {
        return [PSCustomObject]@{
            Entry  = $null
            Anchor = $anchor
        }
    }

    $normalizedStem = Get-StemPath $target
    $candidates = @($MarkdownEntries | Where-Object { $_.StemRelative -eq $normalizedStem })

    if ($candidates.Count -eq 0) {
        $baseName = [System.IO.Path]::GetFileName($normalizedStem)
        $candidates = @($MarkdownEntries | Where-Object { $_.BaseName -eq $baseName })
    }

    if ($candidates.Count -ne 1) {
        return $null
    }

    return [PSCustomObject]@{
        Entry  = $candidates[0]
        Anchor = $anchor
    }
}

function Convert-WikiLinks {
    param(
        [string]$Content,
        [string]$CurrentTargetPath,
        [string]$ProjectOutputRoot,
        [object[]]$MarkdownEntries
    )

    $pattern = '\[\[([^\]]+)\]\]'

    return [regex]::Replace($Content, $pattern, {
        param($match)

        $inner = $match.Groups[1].Value
        $parts = $inner -split '\|', 2
        $targetSpec = $parts[0].Trim()
        $label = if ($parts.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $parts[1].Trim()
        } else {
            ""
        }

        $resolved = Resolve-WikiLinkTarget -TargetSpec $targetSpec -MarkdownEntries $MarkdownEntries
        if (-not $resolved) {
            return $match.Value
        }

        if ($null -eq $resolved.Entry) {
            if ([string]::IsNullOrWhiteSpace($label)) {
                $label = $resolved.Anchor.TrimStart('#')
            }

            return "[{0}]({1})" -f $label, $resolved.Anchor
        }

        $targetOutputPath = Join-Path $ProjectOutputRoot ($resolved.Entry.OutputRelative -replace '/', '\\')
        $currentDirectory = Split-Path -Parent $CurrentTargetPath
        $relativeLink = Get-RelativePath -FromDirectory $currentDirectory -ToPath $targetOutputPath
        $relativeLink = To-ForwardSlash $relativeLink

        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = $resolved.Entry.BaseName
        }

        return "[{0}]({1}{2})" -f $label, $relativeLink, $resolved.Anchor
    })
}

function Copy-ProjectFile {
    param(
        [System.IO.FileInfo]$File,
        [string]$ProjectSourceRoot,
        [string]$ProjectOutputRoot,
        [object[]]$MarkdownEntries
    )

    $relativePath = Get-RelativePath -FromDirectory $ProjectSourceRoot -ToPath $File.FullName
    $relativePath = To-ForwardSlash $relativePath
    $outputInfo = Get-OutputPathInfo -ProjectRelativePath $relativePath
    $targetPath = Join-Path $ProjectOutputRoot ($outputInfo.OutputRelative -replace '/', '\\')
    $targetDirectory = Split-Path -Parent $targetPath

    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null

    if ($File.Extension -ieq ".md") {
        $content = [System.IO.File]::ReadAllText($File.FullName, [System.Text.Encoding]::UTF8)
        $content = Convert-WikiLinks -Content $content -CurrentTargetPath $targetPath -ProjectOutputRoot $ProjectOutputRoot -MarkdownEntries $MarkdownEntries
        [System.IO.File]::WriteAllText($targetPath, $content, $utf8Bom)
        return
    }

    Copy-Item -Path $File.FullName -Destination $targetPath -Force
}

function Generate-ProjectIndex {
    param(
        [string]$ProjectName,
        [string]$ProjectSourceRoot,
        [string]$ProjectOutputRoot,
        [object[]]$DocEntries,
        [object[]]$SupplementEntries
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $ProjectName")
    $lines.Add("")
    $lines.Add("这个项目来自 ``D:\obsidian\工作\$ProjectName``。现在项目文档和补充页都以 Obsidian 工作目录为唯一来源。")
    $lines.Add("")
    $lines.Add("## 项目概况")
    $lines.Add("")
    $lines.Add("- 文档数：``$($DocEntries.Count)``")
    $lines.Add("- 补充页数：``$($SupplementEntries.Count)``")
    $lines.Add("- 源目录：``$ProjectSourceRoot``")
    $lines.Add("- 站点文档目录：``$ProjectOutputRoot\文档``")
    $lines.Add("- 站点补充页目录：``$ProjectOutputRoot\$supplementFolderName``")
    $lines.Add("")

    if ($SupplementEntries.Count -gt 0) {
        $lines.Add("## 项目补充页")
        $lines.Add("")

        foreach ($entry in @($SupplementEntries | Sort-Object NavRelativePath)) {
            $title = [System.IO.Path]::GetFileNameWithoutExtension($entry.NavRelativePath)
            $lines.Add("- [$title](./$supplementFolderName/$($entry.NavRelativePath))")
        }

        $lines.Add("")
    }

    $lines.Add("## 原始文档入口")
    $lines.Add("")

    if ($DocEntries.Count -eq 0) {
        $lines.Add("当前项目下还没有原始文档。")
        $lines.Add("")
    } else {
        $lines.Add("| 文档 | 入口 |")
        $lines.Add("| ---- | ---- |")

        foreach ($entry in @($DocEntries | Sort-Object NavRelativePath)) {
            $lines.Add("| ``$($entry.NavRelativePath)`` | [查看](./文档/$($entry.NavRelativePath)) |")
        }

        $lines.Add("")
    }

    $lines.Add("## 使用建议")
    $lines.Add("")
    $lines.Add("1. 项目原始文档直接写在项目目录中。")
    $lines.Add("2. 如果需要专题索引、阅读导航或总结页，请放到项目里的 ``$supplementFolderName/`` 目录。")
    $lines.Add("3. 后续只需要在 Obsidian 的 ``D:\obsidian\工作`` 中维护内容，然后一键发布即可。")
    $lines.Add("")

    Write-Utf8File -Path (Join-Path $ProjectOutputRoot "index.md") -Content ($lines -join "`r`n")
}

function Generate-ProjectsIndex {
    param([object[]]$ProjectInfos)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 工作项目总览")
    $lines.Add("")
    $lines.Add("这里把 ``D:\obsidian\工作`` 下的一级目录视作独立项目，按项目方式分门别类展示。")
    $lines.Add("")
    $lines.Add("## 项目列表")
    $lines.Add("")

    if ($ProjectInfos.Count -eq 0) {
        $lines.Add("当前还没有可展示的项目。")
        $lines.Add("")
    } else {
        $lines.Add("| 项目 | 文档数 | 补充页数 | 入口 |")
        $lines.Add("| ---- | ---- | ---- | ---- |")

        foreach ($projectInfo in @($ProjectInfos | Sort-Object Name)) {
            $lines.Add("| ``$($projectInfo.Name)`` | ``$($projectInfo.DocCount)`` | ``$($projectInfo.SupplementCount)`` | [进入项目](./$($projectInfo.Name)/index.md) |")
        }

        $lines.Add("")
        $lines.Add("## 推荐使用方式")
        $lines.Add("")
        $lines.Add("1. 先从项目总览进入，再打开对应项目主页。")
        $lines.Add("2. 原始文档和补充页都维护在 Obsidian 的工作目录里。")
        $lines.Add("3. 项目里的 ``$supplementFolderName/`` 目录适合放索引页、专题页和总结页。")
        $lines.Add("")
    }

    Write-Utf8File -Path (Join-Path $projectsRoot "index.md") -Content ($lines -join "`r`n")
}

function Add-NavEntries {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string[]]$RelativePaths,
        [string]$OutputPrefix,
        [int]$Level
    )

    $emittedDirectories = @{}

    foreach ($relativePath in @($RelativePaths | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        $segments = $relativePath -split '/'

        if ($segments.Count -gt 1) {
            for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
                $directoryPath = ($segments[0..$i] -join '/')

                if ($emittedDirectories.ContainsKey($directoryPath)) {
                    continue
                }

                $emittedDirectories[$directoryPath] = $true
                $Lines.Add(("{0}- {1}:" -f (Get-NavIndent ($Level + $i)), $segments[$i]))
            }
        }

        $title = [System.IO.Path]::GetFileNameWithoutExtension($segments[$segments.Count - 1])
        $Lines.Add(("{0}- {1}: {2}/{3}" -f (Get-NavIndent ($Level + $segments.Count - 1)), $title, $OutputPrefix, $relativePath))
    }
}

function Write-MkDocsConfig {
    param([object[]]$ProjectInfos)

    $lines = New-Object System.Collections.Generic.List[string]

    @(
        "site_name: 工作项目文档站",
        "site_description: 把 Obsidian 工作目录中的项目文档发布为可在线浏览的站点",
        "site_author: Eric Lee",
        "",
        "theme:",
        "  name: material",
        "  language: zh",
        "  features:",
        "    - navigation.indexes",
        "    - navigation.sections",
        "    - navigation.expand",
        "    - navigation.top",
        "    - navigation.path",
        "    - navigation.footer",
        "    - search.highlight",
        "    - search.suggest",
        "    - content.code.copy",
        "    - content.tabs.link",
        "    - toc.follow",
        "  palette:",
        "    - scheme: default",
        "      primary: teal",
        "      accent: amber",
        "      toggle:",
        "        icon: material/weather-night",
        "        name: 切换到深色模式",
        "    - scheme: slate",
        "      primary: teal",
        "      accent: amber",
        "      toggle:",
        "        icon: material/weather-sunny",
        "        name: 切换到浅色模式",
        "",
        "plugins:",
        "  - search",
        "",
        "extra_css:",
        "  - stylesheets/extra.css",
        "",
        "markdown_extensions:",
        "  - admonition",
        "  - attr_list",
        "  - def_list",
        "  - footnotes",
        "  - md_in_html",
        "  - tables",
        "  - toc:",
        "      permalink: true",
        "  - pymdownx.details",
        "  - pymdownx.highlight:",
        "      anchor_linenums: true",
        "  - pymdownx.inlinehilite",
        "  - pymdownx.snippets",
        "  - pymdownx.superfences",
        "  - pymdownx.tabbed:",
        "      alternate_style: true",
        "",
        "nav:"
    ) | ForEach-Object {
        $lines.Add($_)
    }

    $lines.Add(("{0}- 首页: index.md" -f (Get-NavIndent 0)))
    $lines.Add(("{0}- 工作项目总览: 项目/index.md" -f (Get-NavIndent 0)))

    foreach ($projectInfo in @($ProjectInfos | Sort-Object Name)) {
        $projectName = $projectInfo.Name
        $docPaths = @($projectInfo.DocEntries | Sort-Object NavRelativePath | ForEach-Object { $_.NavRelativePath })
        $supplementPaths = @($projectInfo.SupplementEntries | Sort-Object NavRelativePath | ForEach-Object { $_.NavRelativePath })

        $lines.Add(("{0}- {1}:" -f (Get-NavIndent 0), $projectName))
        $lines.Add(("{0}- 项目主页: 项目/{1}/index.md" -f (Get-NavIndent 1), $projectName))

        if ($supplementPaths.Count -gt 0) {
            $lines.Add(("{0}- ${supplementFolderName}:" -f (Get-NavIndent 1)))
            Add-NavEntries -Lines $lines -RelativePaths $supplementPaths -OutputPrefix "项目/$projectName/$supplementFolderName" -Level 2
        }

        if ($docPaths.Count -gt 0) {
            $lines.Add(("{0}- 文档:" -f (Get-NavIndent 1)))
            Add-NavEntries -Lines $lines -RelativePaths $docPaths -OutputPrefix "项目/$projectName/文档" -Level 2
        }
    }

    $lines.Add(("{0}- 站点维护:" -f (Get-NavIndent 0)))
    $lines.Add(("{0}- 发布与同步: 站点维护/发布与同步.md" -f (Get-NavIndent 1)))

    Write-Utf8File -Path (Join-Path $projectRoot "mkdocs.yml") -Content ($lines -join "`r`n")
}

if (-not (Test-Path $SourceRoot)) {
    throw "源目录不存在：$SourceRoot"
}

New-Item -ItemType Directory -Force -Path $projectsRoot | Out-Null

$projectDirectories = @(Get-ChildItem -Path $SourceRoot -Directory | Sort-Object Name)
$projectNames = @($projectDirectories | ForEach-Object { $_.Name })

$existingProjectDirectories = @(Get-ChildItem -Path $projectsRoot -Directory -ErrorAction SilentlyContinue)
foreach ($existingDirectory in $existingProjectDirectories) {
    if ($projectNames -notcontains $existingDirectory.Name) {
        Remove-Item -Path $existingDirectory.FullName -Recurse -Force
    }
}

$projectInfos = @()

foreach ($projectDirectory in $projectDirectories) {
    $projectName = $projectDirectory.Name
    $projectSourceRoot = $projectDirectory.FullName
    $projectOutputRoot = Join-Path $projectsRoot $projectName

    if (Test-Path $projectOutputRoot) {
        Remove-Item -Path $projectOutputRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $projectOutputRoot | Out-Null

    $markdownEntries = @(Get-ProjectMarkdownEntries -ProjectSourceRoot $projectSourceRoot)
    $files = Get-ChildItem -Path $projectSourceRoot -Recurse -File -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        Copy-ProjectFile -File $file -ProjectSourceRoot $projectSourceRoot -ProjectOutputRoot $projectOutputRoot -MarkdownEntries $markdownEntries
    }

    $docEntries = @($markdownEntries | Where-Object { $_.Category -eq "document" })
    $supplementEntries = @($markdownEntries | Where-Object { $_.Category -eq "supplement" })

    Generate-ProjectIndex -ProjectName $projectName -ProjectSourceRoot $projectSourceRoot -ProjectOutputRoot $projectOutputRoot -DocEntries $docEntries -SupplementEntries $supplementEntries

    $projectInfos += [PSCustomObject]@{
        Name             = $projectName
        DocCount         = $docEntries.Count
        SupplementCount  = $supplementEntries.Count
        DocEntries       = $docEntries
        SupplementEntries = $supplementEntries
    }
}

Generate-ProjectsIndex -ProjectInfos $projectInfos
Write-MkDocsConfig -ProjectInfos $projectInfos

Write-Host ("同步完成：{0} -> {1}" -f $SourceRoot, $projectsRoot)
Write-Host ("项目数量：{0}" -f $projectInfos.Count)
