# ob_githubpage

这个目录用于把 `D:\obsidian\工作\一句话编程` 中的 Markdown 文档发布成一个可在线浏览的站点。

## 当前内容

- `MkDocs + Material` 站点配置
- Obsidian 文档同步脚本
- GitHub Pages 自动发布工作流
- 面向模块文档浏览的 wiki 风格首页与索引页

## 本地预览

1. 同步文档：

   ```powershell
   .\scripts\sync_notes.ps1
   ```

2. 激活虚拟环境：

   ```powershell
   .\.venv\Scripts\Activate.ps1
   ```

3. 启动本地预览：

   ```powershell
   mkdocs serve
   ```

4. 构建静态站点：

   ```powershell
   mkdocs build --strict
   ```

## 文档来源

- 源目录：`D:\obsidian\工作\一句话编程`
- 站点文档目录：`D:\code\ob_githubpage\docs\一句话编程`

## 常用命令

```powershell
.\scripts\sync_notes.ps1
.\.venv\Scripts\Activate.ps1
mkdocs serve
mkdocs build --strict
```

## 推送到 GitHub 后的发布方式

1. 确保仓库已推送到 GitHub。
2. 在仓库 `Settings -> Pages` 中将 `Source` 设为 `GitHub Actions`。
3. 后续每次推送到 `main` 分支，工作流都会自动构建并发布。
