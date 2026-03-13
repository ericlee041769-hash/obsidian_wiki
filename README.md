# ob_githubpage

这个目录用于把 `D:\obsidian\工作` 里的项目文档发布成一个可在线浏览的 wiki 站点。

## 现在的维护方式

后续建议只维护一个地方：`D:\obsidian\工作`

- 项目普通文档：直接写在 `D:\obsidian\工作\<项目名>\...`
- 项目补充页：写在 `D:\obsidian\工作\<项目名>\补充页\...`

同步后：

- 普通文档会发布到 `docs\项目\<项目名>\文档`
- 补充页会发布到 `docs\项目\<项目名>\补充页`
- 左侧导航会按项目、补充页、文档目录树自动生成

## 常用命令

1. 同步 Obsidian 文档到站点：

```powershell
.\scripts\sync_notes.ps1
```

2. 激活虚拟环境：

```powershell
.\.venv\Scripts\Activate.ps1
```

3. 本地预览：

```powershell
mkdocs serve
```

4. 严格构建检查：

```powershell
mkdocs build --strict
```

## 文档来源

- 工作目录：`D:\obsidian\工作`
- 站点文档目录：`D:\code\ob_githubpage\docs\项目`

## GitHub Pages 发布方式

1. 确保仓库已推送到 GitHub。
2. 在仓库的 `Settings -> Pages` 中将来源设置为 `GitHub Actions`。
3. 后续每次推送到 `main` 分支，工作流都会自动构建并发布站点。