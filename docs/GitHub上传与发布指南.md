# GitHub 上传与 Release 发布指南

本文说明如何检查本地改动、上传 `3.0` 分支，以及发布包含最新安装脚本的 Release。命令默认在仓库根目录运行。

## 上传前检查

```powershell
git status --short
git diff --check
git diff --stat
```

确认没有把 `config/app.conf`、数据库密码、日志、运行数据、`build/` 或 `dist/` 临时产物提交到仓库。示例配置 `config/app.conf.example` 可以提交。

先同步远程分支，再暂存并检查提交内容：

```powershell
git switch 3.0
git pull --rebase origin 3.0
git add README.md README.zh-CN.md config scripts docs .github
git status --short
git diff --cached --check
git commit -m "fix: repair Chinese docs and latest installer"
git push origin 3.0
```

如果提交时 Git 要求登录，使用 Git Credential Manager 浏览器流程完成认证。不要将访问令牌写入命令、脚本或仓库文件。

## 发布最新版本

安装入口使用 `releases/latest/download/install-release.sh`。只有把更新后的安装脚本作为 Release 资产发布，Linux 一键命令才会取到最新脚本。当前仓库的 Release 工作流由 `v*` 标签触发，因此发布新版本时先确认版本号未被使用，再创建并推送标签：

```powershell
git tag --list "v*"
git tag -a v3.0.9 -m "ZbxTable v3.0.9"
git push origin v3.0.9
```

推送标签后，在 GitHub 仓库 **Actions** 页面等待 Release 工作流完成。它会构建前端和后端、运行 Go 检查、生成 Linux 压缩包与校验文件并创建 Release。工作流资产清单还应包含交互式安装器、Linux/Windows 安装器和卸载器；检查 `.github/workflows/release.yml` 中 `Create GitHub Release` 的 `files` 配置，确保包含：

```text
scripts/install-release.sh
scripts/install-release.ps1
scripts/install-release.bat
scripts/uninstall.sh
scripts/uninstall.ps1
scripts/uninstall.bat
```

首次发布标签前确认 `go test ./...`、`go vet ./...`、前端构建和发布包检查通过。若动作失败，修复原因后增加新的补丁版本标签，不要复用已经发布的标签。

## 验证发布和安装入口

先打开 GitHub Releases 页面，确认最新正式版标签和下载资产。再检查 latest 下载地址返回成功：

```powershell
curl.exe -fIL https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.sh
curl.exe -fIL https://github.com/linguyuebai/zbxtable/releases/latest/download/uninstall.sh
```

在 Linux 上查看脚本版本和参数：

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.sh -o install-release.sh
head -n 25 install-release.sh
bash install-release.sh --help
```

安装器菜单默认使用 GitHub `latest` Release。命令行安装同样建议使用 latest 地址：

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.sh | sudo bash -s -- --install-deps --install-root=/opt/zbxtable
```

若需固定安装版本，将下载链接替换为：

```text
https://github.com/linguyuebai/zbxtable/releases/download/v3.0.9/install-release.sh
```

## 安装、修复和更新

交互模式：

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.sh | sudo bash
```

按提示选择 systemd、Docker、更新、修复、卸载或退出。更新和修复会保留已有配置。Linux 安装默认使用 `8089` 端口，默认新数据库名为 `zbxtable_lg`；已有 `config/app.conf` 不会被重写。

常用命令行参数：

| 参数 | 用途 |
| --- | --- |
| `--install-deps` | 检查并安装 Linux 基础依赖。 |
| `--docker-install --port=8089` | 安装 Docker 并部署容器，可自定义宿主机端口。 |
| `--repair` | 使用 latest Release 修复当前安装并保留配置。 |
| `--update` | 更新当前安装并保留配置。 |
| `--uninstall` | 进入卸载流程。 |
| `--purge` | 卸载时同时清理配置文件，并进入数据库表清理确认流程。 |
| `--yes` | 跳过程序文件卸载确认；不会跳过数据库删表的二次确认。 |

## 卸载和数据库安全

默认卸载会保留 `config/app.conf`。使用 `--purge` 时，卸载器读取配置并尝试列出当前账号可访问、名称含 `zbxtable` 且包含 ZbxTable 自有表的数据库。选择数据库后，卸载器显示将要删除的表，并要求输入 `DELETE TABLES`。它只删除名称严格匹配 `zbxtable_` 前缀的表，不执行 `DROP DATABASE`，也不删除 Zabbix 原生表或停止 Zabbix 服务。

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/uninstall.sh -o uninstall.sh
sudo bash uninstall.sh --install-root=/opt/zbxtable --runtime-root=/usr/local/zbxtable --purge
```

自动化环境没有交互终端、数据库客户端未安装、配置不可读或数据库无法连接时，卸载器会跳过数据库清理并输出原因；文件卸载仍可继续。数据库权限不足时，应由数据库管理员备份后手工处理。

## 本地构建发布包

Linux/macOS：

```bash
./scripts/package-release.sh
```

Windows PowerShell：

```powershell
$env:ZBXTABLE_VERSION = 'v3.0.9'
.\scripts\package-release.ps1
```

发布包不应包含真实配置、数据库密码、日志和运行数据。发布前检查校验文件，并在测试机验证从 `latest` 地址下载、安装、升级和卸载流程。
