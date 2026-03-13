param(
    [Parameter(Mandatory = $true)]
    [string]$RepoUrl
)

$ErrorActionPreference = "Stop"

git rev-parse --is-inside-work-tree | Out-Null

$existing = git remote

if ($existing -match '(^|\s)origin(\s|$)') {
    git remote set-url origin $RepoUrl
    Write-Host "已更新 origin -> $RepoUrl"
} else {
    git remote add origin $RepoUrl
    Write-Host "已添加 origin -> $RepoUrl"
}

Write-Host "当前远程："
git remote -v
