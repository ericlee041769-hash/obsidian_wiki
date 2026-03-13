param(
    [string]$SourceRoot = "D:\obsidian\工作\一句话编程"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$targetRoot = Join-Path $projectRoot "docs\一句话编程"
$subTargetRoot = Join-Path $targetRoot "下位机文档"

New-Item -ItemType Directory -Force -Path $targetRoot, $subTargetRoot | Out-Null

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Copy-MarkdownFile {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$AiLink
    )

    $content = [System.IO.File]::ReadAllText($SourcePath, $utf8NoBom)

    if ($AiLink) {
        $content = $content.Replace('[[AI一句话编程]]中的', ('[AI一句话编程]({0})中的' -f $AiLink))
        $content = $content.Replace('[[AI一句话编程]]', ('[AI一句话编程]({0})' -f $AiLink))
    }

    Write-Utf8File -Path $TargetPath -Content $content
}

$topLevelFiles = @(
    "AI一句话编程.md",
    "硬件接线.md"
)

foreach ($file in $topLevelFiles) {
    $sourcePath = Join-Path $SourceRoot $file
    $targetPath = Join-Path $targetRoot $file
    Copy-MarkdownFile -SourcePath $sourcePath -TargetPath $targetPath -AiLink "AI一句话编程.md"
}

$moduleFiles = Get-ChildItem -Path (Join-Path $SourceRoot '下位机文档') -File -Filter '*.md' | Sort-Object Name

foreach ($file in $moduleFiles) {
    $targetPath = Join-Path $subTargetRoot $file.Name
    Copy-MarkdownFile -SourcePath $file.FullName -TargetPath $targetPath -AiLink "../AI一句话编程.md"
}

Write-Host "同步完成：$SourceRoot -> $targetRoot"
