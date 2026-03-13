# ob_githubpage

这个目录用于把 `D:\obsidian\工作` 里的项目文档发布成一个可在线浏览的 wiki 站点。

## 现在的发布结构

- `D:\obsidian\工作` 下的每个一级目录都会被视作一个独立项目。
- 同步后的站点内容输出到 `docs\项目\<项目名>\文档`。
- 每个项目还会自动生成一个项目主页 `docs\项目\<项目名>\index.md`。
- 项目根目录下人工维护的补充页会被保留，例如 `协议速览.md`、`模块索引.md`。

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