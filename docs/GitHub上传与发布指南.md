# GitHub 上传、打包与一键安装

本文说明如何检查工作区、生成源码压缩包、创建 GitHub Release，并在 Linux 或 Windows 上下载 Release 自动安装。命令默认在仓库根目录执行。

## 发布前检查

先检查待提交文件，确认 `config/app.conf`、数据库密码、日志、运行数据及本地构建目录没有进入版本库：

```powershell
git status --short
git check-ignore -v config/app.conf log build dist
git diff --check
```

`config/app.conf.example` 是可提交的模板；实际配置 `config/app.conf` 不应提交。检查完再添加和提交代码：

```bash
git switch 3.0
git pull --rebase origin 3.0
git add -A
git status --short
git diff --cached --check
git commit -m "feat: 完善巡检和发布安装流程"
git push origin 3.0
```

首次推送前应确认 `origin` 指向自己的仓库或已获授权的上游仓库。此步骤只推送代码分支；创建 Release 是后续单独操作。

## 一键检查并生成发布包

脚本自动检查必需文件、敏感/构建目录和 `git diff --check`，随后在 `dist/` 生成 `zbxtable-v3.0.7/` 发布目录、ZIP、Linux 可用的 TAR.GZ 及各自 SHA256 文件，并收集 Windows/Linux 一键安装和卸载脚本。`dist/` 和发布临时目录已加入忽略规则。

### 应该上传哪个压缩包？

本项目当前使用“源码完整发布包”方式：

| 文件 | 用途 |
|---|---|
| `zbxtable-v3.0.7-source.tar.gz` | Linux、Ubuntu、Debian、CentOS 推荐使用；保留 Linux 脚本权限，包含代码、文档、配置模板、安装/运行脚本以及已存在的前端文件，是服务器端优先选择的完整包。 |
| `zbxtable-v3.0.7-source.zip` | Windows Server 推荐使用；包含代码、文档、配置模板和安装/运行脚本。Windows 生成的 ZIP 可能不含前端构建产物，安装脚本会自动构建前端。 |
| 同名 `.sha256` | 下载后校验文件完整性，必须和对应压缩包配套使用。 |

`dist/zbxtable-v3.0.7/` 是解压后的完整目录，适合通过 `scp` 或内网文件传输直接上传到 Linux；上传目录后可以直接运行 `scripts/install.sh`。正式上传 GitHub 时上传压缩包、校验文件和入口脚本即可，不需要上传 `dist/` 整个目录。

因此，Linux 服务器上传 `source.tar.gz` 和对应 `.tar.gz.sha256`；Windows 服务器上传 `source.zip` 和对应 `.zip.sha256`。不要上传旧版本名称中带 `dirty` 的开发包。版本号应替换成你实际发布的版本，例如 `v3.0.8`。

压缩包中不放真实数据库密码、日志、运行数据和本地 `build/` 目录。Linux TAR.GZ 在 Git Bash/Linux 环境打包时会包含已有的 `api/v1/web/web/`；如果包内没有前端文件，安装脚本会自动尝试下载 `zbxtable-web` 并构建。

Windows PowerShell：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\publish-release.ps1 -Version v3.0.7
```

Linux/macOS：

```bash
bash scripts/publish-release.sh
```

脚本默认只检查和打包，不会上传。指定版本可使用 `ZBXTABLE_VERSION` 环境变量；Windows 也可传 `-Version`。未指定时使用 `git describe` 生成版本名。Linux 端验证校验和：

```bash
sha256sum -c dist/*.tar.gz.sha256
```

Windows 端可验证：

```powershell
Get-FileHash .\dist\*.zip -Algorithm SHA256
```

打包完成后，可以先检查压缩包中是否存在关键文件：

```bash
tar -tzf dist/zbxtable-v3.0.7-source.tar.gz | grep -E '(^|/)(README.zh-CN.md|config/app.conf.example|scripts/install.sh|scripts/run.sh)$'
```

Windows PowerShell：

```powershell
tar.exe -tf .\dist\zbxtable-v3.0.7-source.zip | Select-String 'README.zh-CN.md|config/app.conf.example|scripts/install.ps1|scripts/run.ps1'
```

发布包包括代码、文档、安装脚本和示例配置，不包括真实 `config/app.conf`、日志、运行数据和 `build/`、`dist/`。Linux 端若已有构建好的 `api/v1/web/web/`，会把前端一并打入包；没有时安装步骤会尝试下载并构建前端。

## 创建 GitHub Release 并上传资产

先推送相应代码分支并确认版本号，然后登录 GitHub CLI：

```bash
gh auth login
```

Windows：

```powershell
.\scripts\publish-release.ps1 -Version v3.0.7 -Upload
```

发布到自己的仓库时：

```powershell
.\scripts\publish-release.ps1 `
  -Version v3.0.7 `
  -Repository your-name/zbxtable `
  -Upload
```

Linux/macOS：

```bash
ZBXTABLE_VERSION=v3.0.7 bash scripts/publish-release.sh --upload
```

Linux 发布到自己的仓库：

```bash
ZBXTABLE_VERSION=v3.0.7 \
  bash scripts/publish-release.sh \
  --repository=your-name/zbxtable \
  --upload
```

上传会创建 `v3.0.7` Release，并附上 ZIP/TAR.GZ、校验和和安装脚本。需要先审阅 Release 再公开时，加 `-Draft`（PowerShell）或 `--draft`（Shell）。脚本检查默认开启；只有在有意跳过时才传 `-SkipChecks` 或 `--skip-checks`。

也可以在 GitHub 网页中手工上传：进入仓库 **Releases → Draft a new release**，填写 Tag（例如 `v3.0.7`），把以下文件拖到 Assets：

```text
zbxtable-v3.0.7-source.tar.gz
zbxtable-v3.0.7-source.tar.gz.sha256
zbxtable-v3.0.7-source.zip
zbxtable-v3.0.7-source.zip.sha256
scripts/install-release.sh
scripts/install-release.ps1
scripts/install-release.bat
scripts/install.sh
scripts/install.ps1
scripts/install.bat
scripts/bootstrap-linux.sh
scripts/uninstall.sh
scripts/uninstall.ps1
scripts/uninstall.bat
```

网页上传后点击 **Publish release**。只有 Release 已发布并包含这些资产时，`releases/latest/download/...` 下载地址才会生效。

## 从 GitHub Release 自动安装

自动安装器从 GitHub Releases API 下载最新 Release 或指定版本，验证 SHA256，解压并调用仓库安装脚本。它不会停止或修改 Zabbix 服务。首次部署会提示数据库连接信息，配置默认连接现有 Zabbix 数据库；请使用有建表权限的独立数据库账号，并确认应用端口空闲。完整 TAR.GZ 已包含前端时，服务器只需要 Go 1.24+；如果压缩包没有前端，安装脚本才需要 Git、Node.js/npm（若有 yarn.lock 且安装了 Yarn，也可用 Yarn）以及网络访问 GitHub/npm。跳过前端构建可传 `--skip-frontend` / `-SkipFrontend`，此时以 API 模式运行。

### 方式一：服务器直接从 Release 安装（推荐）

Ubuntu、Debian、CentOS 等 Linux：需要 `curl`、`tar`、`sha256sum`、`python3`、Go 1.24+、Git 和 Node.js/npm。下载脚本后执行：

```bash
curl -fsSL https://github.com/canghai908/zbxtable/releases/latest/download/install-release.sh -o install-release.sh
chmod +x install-release.sh
sudo bash install-release.sh --install-root=/opt/zbxtable
```

首次部署且希望脚本自动安装基础环境（curl、tar、Python、Git、Node.js/npm，以及 Go 1.24.0）时：

```bash
sudo bash install-release.sh --install-deps --install-root=/opt/zbxtable
```

`--install-deps` 只支持 apt、dnf、yum、zypper、apk，会先检查系统包管理器；已有 Go 1.24+ 时不会覆盖。没有该参数时脚本只检测环境并在缺少依赖时停止。

安装指定版本：

```bash
sudo bash install-release.sh --version=v3.0.7 --install-root=/opt/zbxtable
```

Windows Server：需要 PowerShell 5.1+、Go 1.24+、Git、Node.js/npm。以管理员 PowerShell 执行：

```powershell
iwr https://github.com/canghai908/zbxtable/releases/latest/download/install-release.ps1 -OutFile install-release.ps1
powershell.exe -ExecutionPolicy Bypass -File .\install-release.ps1 -InstallRoot C:\ProgramData\zbxtable
```

### 方式二：先上传完整压缩包，再运行包内脚本

Linux：

```bash
scp dist/zbxtable-v3.0.7-source.tar.gz dist/zbxtable-v3.0.7-source.tar.gz.sha256 user@server:/tmp/
ssh user@server
sudo mkdir -p /opt/zbxtable-src
sudo tar -xzf /tmp/zbxtable-v3.0.7-source.tar.gz -C /opt/zbxtable-src --strip-components=1
cd /opt/zbxtable-src
sudo sha256sum -c /tmp/zbxtable-v3.0.7-source.tar.gz.sha256
sudo env ZBXTABLE_DB_NAME=zabbix ZBXTABLE_DB_USER=zabbix ZBXTABLE_DB_PASS='数据库密码' bash scripts/install.sh
sudo bash scripts/run.sh
```

如果使用 systemd 并以 root 执行安装，安装脚本会创建 `zbxtable` 服务；安装后执行 `sudo systemctl start zbxtable`，查看状态用 `sudo systemctl status zbxtable`。

也可以直接上传已生成的目录：

```bash
scp -r dist/zbxtable-v3.0.7 user@server:/tmp/
ssh user@server
sudo rm -rf /opt/zbxtable
sudo mv /tmp/zbxtable-v3.0.7 /opt/zbxtable
cd /opt/zbxtable
sudo env ZBXTABLE_DB_NAME=zabbix ZBXTABLE_DB_USER=zabbix \
  ZBXTABLE_DB_PASS='数据库密码' bash scripts/install.sh
sudo systemctl start zbxtable
```

如果是直接上传目录且服务器还没有安装依赖，可先执行：

```bash
sudo bash scripts/bootstrap-linux.sh
sudo env ZBXTABLE_DB_NAME=zabbix ZBXTABLE_DB_USER=zabbix \
  ZBXTABLE_DB_PASS='数据库密码' bash scripts/install.sh
```

Windows PowerShell：

```powershell
Expand-Archive .\zbxtable-v3.0.7-source.zip -DestinationPath C:\Temp\zbxtable
cd C:\Temp\zbxtable\zbxtable-v3.0.7
Copy-Item config\app.conf.example config\app.conf
notepad config\app.conf
powershell.exe -ExecutionPolicy Bypass -File .\scripts\install.ps1
powershell.exe -ExecutionPolicy Bypass -File .\scripts\run.ps1
```

把 `config/app.conf` 中的数据库地址、账号、密码、库名和 `httpport` 填好后再运行安装。已有配置升级时不要用示例文件覆盖真实配置。

安装指定版本：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install-release.ps1 -Version v3.0.7 -InstallRoot C:\ProgramData\zbxtable
```

目标目录已存在时脚本会停止；传 `--force` / `-Force` 才会替换程序文件，现有 `config/app.conf` 会保留。务必先备份配置和数据库。Linux root 安装会创建/启用 `zbxtable` systemd 服务，但不会自动停止 Zabbix；检查端口冲突后可用 `systemctl start zbxtable` 启动。Windows 安装完成后运行 `scripts\run.ps1`。

### 一键卸载

卸载脚本只管理名为 `zbxtable` 的服务和 ZbxTable 自身目录，不会停止 Zabbix Server、Zabbix Agent、Zabbix Proxy，也不会删除共用数据库中的 Zabbix 原生表。

Linux 默认删除程序和运行文件，但保留 `config/app.conf`：

```bash
cd /opt/zbxtable
sudo bash scripts/uninstall.sh --install-root=/opt/zbxtable --yes
```

如果安装目录已被误删，也可以直接从 Release 下载卸载脚本：

```bash
curl -fsSL https://github.com/canghai908/zbxtable/releases/latest/download/uninstall.sh -o uninstall.sh
chmod +x uninstall.sh
sudo bash uninstall.sh --install-root=/opt/zbxtable --runtime-root=/usr/local/zbxtable --purge --yes
```

彻底删除程序、配置和目录：

```bash
sudo bash scripts/uninstall.sh \
  --install-root=/opt/zbxtable \
  --runtime-root=/usr/local/zbxtable \
  --purge --yes
```

不带 `--yes` 时会要求输入 `DELETE` 确认。`--purge` 只删除 ZbxTable 文件，不删除 Zabbix 数据库、Zabbix 服务或数据库中的 Zabbix 表。安装脚本创建的 `zbxtable` 系统用户默认保留，确认无其他用途后再手工删除。

Windows PowerShell：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -InstallRoot C:\ProgramData\zbxtable
```

也可以直接下载卸载脚本：

```powershell
iwr https://github.com/canghai908/zbxtable/releases/latest/download/uninstall.ps1 -OutFile uninstall.ps1
powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1 -InstallRoot C:\ProgramData\zbxtable
```

彻底删除：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 `
  -InstallRoot C:\ProgramData\zbxtable -Purge -Yes
```

## 安装后检查

1. 确认 `config/app.conf` 中数据库地址、库名、账号和端口正确，且 Web 端口没有与 Zabbix 冲突。
2. 确认 ZbxTable 数据库账号只拥有运行所需权限；共用数据库时，ZbxTable 自有表使用 `zbxtable_` 前缀。
3. 启动服务并检查日志与 Web 页面；先手动执行一次巡检，确认 Zabbix API、日志监控项和通知媒介工作正常。
4. 生产环境先备份数据库及配置，再启用定时任务。

### 常用运行命令

```bash
# Linux
sudo systemctl status zbxtable
sudo journalctl -u zbxtable -f

# 非 systemd 环境
bash scripts/run.sh
```

```powershell
# Windows
powershell.exe -ExecutionPolicy Bypass -File .\scripts\run.ps1
```

浏览器访问 `http://服务器IP:8088`（如果修改了 `httpport`，使用修改后的端口）。默认账号密码请以项目当前初始化逻辑为准，首次登录后立即修改密码。

Windows 日志采集、异常登录监控、Zabbix 中文界面配置、触发器和邮件通知步骤，参见[Zabbix 巡检与 Windows 日志对接指南](./Zabbix-巡检与Windows日志对接指南.md)。
