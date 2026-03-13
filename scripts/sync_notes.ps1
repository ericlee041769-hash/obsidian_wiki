param(
    [string]$SourceRoot = "D:\obsidian\工作"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$docsRoot = Join-Path $projectRoot "docs"
$projectsRoot = Join-Path $docsRoot "项目"
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

    return [System.Uri]::UnescapeDataString($relativeUri.ToString()) -replace '/', '\'
}

function Get-ProjectMarkdownEntries {
    param([string]$ProjectSourceRoot)

    $entries = @()
    $files = Get-ChildItem -Path $ProjectSourceRoot -Recurse -File -Filter "*.md" -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $relativePath = Get-RelativePath -FromDirectory $ProjectSourceRoot -ToPath $file.FullName
        $relativePath = To-ForwardSlash $relativePath

        $entries += [PSCustomObject]@{
            SourceFullName = $file.FullName
            RelativePath   = $relativePath
            StemRelative   = Get-StemPath $relativePath
            BaseName       = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
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

        $targetOutputPath = Join-Path $ProjectOutputRoot (Join-Path "文档" ($resolved.Entry.RelativePath -replace '/', '\'))
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
    $targetPath = Join-Path $ProjectOutputRoot (Join-Path "文档" $relativePath)
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

function Get-ExistingExtraPages {
    param([string]$ProjectOutputRoot)

    if (-not (Test-Path $ProjectOutputRoot)) {
        return @()
    }

    return @(Get-ChildItem -Path $ProjectOutputRoot -File -Filter "*.md" |
        Where-Object { $_.Name -ne "index.md" } |
        Sort-Object Name)
}

function Generate-ProjectIndex {
    param(
        [string]$ProjectName,
        [string]$ProjectSourceRoot,
        [string]$ProjectOutputRoot,
        [object[]]$MarkdownEntries,
        [System.IO.FileInfo[]]$ExtraPages
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $ProjectName")
    $lines.Add("")
    $lines.Add("这个项目来自 ``D:\obsidian\工作\$ProjectName``。站点会把该目录下的 Markdown 文档整理成一个独立项目，方便在线查看和分享。")
    $lines.Add("")
    $lines.Add("## 项目概况")
    $lines.Add("")
    $lines.Add("- Markdown 文档数：``$($MarkdownEntries.Count)``")
    $lines.Add("- 源目录：``$ProjectSourceRoot``")
    $lines.Add("- 站点目录：``$ProjectOutputRoot\文档``")
    $lines.Add("")

    if ($ExtraPages.Count -gt 0) {
        $lines.Add("## 项目补充页")
        $lines.Add("")

        foreach ($page in $ExtraPages) {
            $pageTitle = [System.IO.Path]::GetFileNameWithoutExtension($page.Name)
            $lines.Add("- [$pageTitle](./$($page.Name))")
        }

        $lines.Add("")
    }

    $lines.Add("## 原始文档入口")
    $lines.Add("")

    if ($MarkdownEntries.Count -eq 0) {
        $lines.Add("当前项目下还没有 Markdown 文档。")
        $lines.Add("")
    } else {
        $lines.Add("| 文档 | 入口 |")
        $lines.Add("| ---- | ---- |")

        foreach ($entry in ($MarkdownEntries | Sort-Object RelativePath)) {
            $lines.Add("| ``$($entry.RelativePath)`` | [查看](./文档/$($entry.RelativePath)) |")
        }

        $lines.Add("")
    }

    $lines.Add("## 使用建议")
    $lines.Add("")
    $lines.Add("1. 先看本页，快速了解这个项目有哪些文档。")
    $lines.Add("2. 再进入 ``文档/`` 目录按结构向下阅读。")
    $lines.Add("3. 如果项目有补充页，可以把它们当作索引页、专题页或阅读导航。")
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
        $lines.Add("| 项目 | Markdown 数量 | 入口 |")
        $lines.Add("| ---- | ---- | ---- |")

        foreach ($projectInfo in ($ProjectInfos | Sort-Object Name)) {
            $lines.Add("| ``$($projectInfo.Name)`` | ``$($projectInfo.MarkdownCount)`` | [进入项目](./$($projectInfo.Name)/index.md) |")
        }

        $lines.Add("")
        $lines.Add("## 推荐使用方式")
        $lines.Add("")
        $lines.Add("1. 先从项目总览进入，再打开对应项目主页。")
        $lines.Add("2. 每个项目主页都会列出自动同步出来的 ``文档/`` 内容。")
        $lines.Add("3. 如果某个项目有补充页，它们会直接出现在项目主页里。")
        $lines.Add("")
    }

    Write-Utf8File -Path (Join-Path $projectsRoot "index.md") -Content ($lines -join "`r`n")
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
    $generatedDocRoot = Join-Path $projectOutputRoot "文档"

    if (Test-Path $generatedDocRoot) {
        Remove-Item -Path $generatedDocRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $generatedDocRoot | Out-Null

    $markdownEntries = @(Get-ProjectMarkdownEntries -ProjectSourceRoot $projectSourceRoot)
    $files = Get-ChildItem -Path $projectSourceRoot -Recurse -File -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        Copy-ProjectFile -File $file -ProjectSourceRoot $projectSourceRoot -ProjectOutputRoot $projectOutputRoot -MarkdownEntries $markdownEntries
    }

    $extraPages = Get-ExistingExtraPages -ProjectOutputRoot $projectOutputRoot
    Generate-ProjectIndex -ProjectName $projectName -ProjectSourceRoot $projectSourceRoot -ProjectOutputRoot $projectOutputRoot -MarkdownEntries $markdownEntries -ExtraPages $extraPages

    $projectInfos += [PSCustomObject]@{
        Name          = $projectName
        MarkdownCount = $markdownEntries.Count
    }
}

Generate-ProjectsIndex -ProjectInfos $projectInfos

Write-Host ("同步完成：{0} -> {1}" -f $SourceRoot, $projectsRoot)
Write-Host ("项目数量：{0}" -f $projectInfos.Count)
