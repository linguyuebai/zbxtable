[English](./README.md) | 简体中文

# ZbxTable

> 当前默认值：Web 端口 `8089`，独立数据库 `zbxtable`。ZbxTable 的自有表始终使用 `zbxtable_` 前缀，因此可以与官方 Zabbix 共存。

### 数据库隔离

新安装建议创建独立的 `zbxtable` 数据库并使用单独账号。安装脚本不会迁移、删除或修改 Zabbix 的 `hosts`、`items`、`history`、`events` 等原生表；只会在配置的数据库中创建 `zbxtable_` 前缀表。若确实需要共用 Zabbix 数据库，可显式设置 `ZBXTABLE_DB_NAME=zabbix`，但仍须授予 ZbxTable 账号创建和读写 `zbxtable_*` 表的权限。

[![Build and Test](https://github.com/canghai908/zbxtable/actions/workflows/build.yml/badge.svg)](https://github.com/canghai908/zbxtable/actions/workflows/build.yml)
[![Release](https://github.com/canghai908/zbxtable/actions/workflows/release.yml/badge.svg)](https://github.com/canghai908/zbxtable/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Go Version](https://img.shields.io/badge/Go-%3E%3D%201.24-blue)](https://golang.org/)

ZbxTable 是一个使用 Go 语言开发的 Zabbix 智能运维平台，提供强大的监控数据展示、告警管理和 AI 智能分析功能。

## 与 Zabbix 共用数据库

ZbxTable 可以直接使用 Zabbix 现有的 MySQL/MariaDB 或 PostgreSQL 数据库，不需要新建数据库。安装时将 `dbname` 填写为 Zabbix 数据库名，并使用具备建表和读写权限的账号即可。ZbxTable 自有表统一使用 `zbxtable_` 前缀，例如 `zbxtable_inspection_policy` 和 `zbxtable_inspection_result`，不会修改 Zabbix 的 `hosts`、`items`、`history` 等原生表；巡检指标通过已配置的 Zabbix API 读取。

## 一键安装和运行

### Linux 交互式菜单

通过同一个入口按提示输入数字，可选择 systemd 安装、Docker 安装、更新、修复、卸载或退出；更新和修复都会保留现有配置，安装时选择版本和 Web 端口，卸载时可选择保留或删除配置：

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/install-release.sh | sudo bash
```

卸载需要输入 `DELETE` 确认，只会移除 ZbxTable 服务、容器和文件，不会删除 Zabbix 服务或共享数据库。自动化或无交互部署仍可使用下方命令行参数。

Linux：

```bash
cd zbxtable
ZBXTABLE_DB_NAME=zbxtable ZBXTABLE_DB_USER=zbxtable ZBXTABLE_DB_PASS='数据库密码' bash scripts/install.sh
bash scripts/run.sh
```

Windows：双击 `scripts\\install.bat` 完成编译和配置，再双击 `scripts\\run.bat` 启动；也可以在 PowerShell 中执行 `scripts\\install.ps1` 和 `scripts\\run.ps1`。脚本默认连接 `127.0.0.1:3306/zabbix`，已有 `config/app.conf` 时不会覆盖配置。

## 上传 GitHub 和生成压缩包

代码归类、敏感文件排除、GitHub 推送、Release 和校验步骤见 [GitHub 上传与发布指南](docs/GitHub上传与发布指南.md)。提交前运行 `git diff --check` 和 `git status --short`；Linux 执行 `./scripts/package-release.sh`，Windows 执行 `scripts\\package-release.bat`。压缩包不包含数据库密码、日志、运行数据和本地构建缓存。

## ✨ 3.0 版本亮点

**ZbxTable 3.0** 是一个里程碑式的版本更新，带来了多项重大功能增强：

- 🤖 **AI 智能分析** - 集成 AI 大模型（Ollama/Deepseek），智能分析告警原因并提供解决方案
- 🌐 **多租户架构** - 支持同时管理多个 Zabbix 实例，实例级别的数据隔离和权限控制
- 📢 **增强的告警管理** - 全新的告警分发规则引擎，支持告警屏蔽、状态追踪和事件日志
- 💾 **数据库优化** - 完整支持 MySQL 和 PostgreSQL，使用 GORM 统一数据访问层
- 🔐 **安全性增强** - 敏感信息加密存储，系统自动生成加密密钥
- ⚡ **缓存系统重构** - 使用 go-cache 替代 Redis，简化部署架构
- 📝 **日志系统升级** - 按日期自动分割，自动压缩历史日志

## 功能特性

### 核心功能
- 🎨 **拓扑管理** - 自定义绘制拓扑图，实时状态显示
- 📊 **设备管理** - 设备分类展示和导出（Linux、Windows、网络设备、存储等）
- 📈 **报表系统** - 导出指定时间段内的 Zabbix 告警和指标数据到 Excel
- 🔍 **告警分析** - 分析特定时间段的告警数据，生成告警 Top 10 等统计
- 📅 **定时任务** - 定时报表生成和自动发送
- 🧾 **设备巡检** - 检查 IP、名称、内存、CPU、磁盘、时间同步和安全日志，并保存结果导出

### 设备巡检与安全检测

巡检策略支持按 Zabbix 实例、主机或主机组配置监控项和阈值，默认检测 CPU、内存总量/使用率、磁盘使用率/剩余容量、时间偏差。通过 Zabbix 日志监控项统计非常用登录 IP、登录失败和暴力破解，并将异常写入 ZbxTable 告警分发渠道。

主要接口：

- `GET/POST/PUT/DELETE /v1/inspection/policies`：巡检策略管理
- `POST /v1/inspection/run`：立即执行策略，请求体 `{"id": 1}`
- `GET /v1/inspection/policies/:id/results`：查询巡检记录
- `GET /v1/inspection/policies/:id/summary`：返回周期汇总和每台设备平均值，可用 `start`、`end` 限定周/月范围
- `POST /v1/inspection/export`：导出巡检 Excel；`include_details=false` 时只导出汇总和设备平均值，适合周报/月报

启用策略后后台默认每 10 分钟执行一次，可通过 `inspection_enabled` 和 `inspection_cron` 调整。巡检数据写入 `zbxtable_inspection_policy`、`zbxtable_inspection_result`，与 Zabbix 原生表隔离。

主机报表支持日报、周报、月报；周报和月报按设备/指标只输出周期平均值，报表数值和百分比固定保留两位小数。月报定时任务可通过 `month_report_enabled`、`month_report_cron` 调整。

### 告警管理
- 📧 **多渠道通知** - 支持邮件、企业微信、Webhook 等多种通知方式
- 🎯 **告警分发** - 灵活的告警规则引擎，支持多维度匹配条件
- 🔕 **告警屏蔽** - 支持时间段、主机、告警级别等多维度屏蔽规则
- 📊 **告警追踪** - 完整的告警状态追踪和事件日志记录
- 🤖 **AI 分析** - 智能分析告警原因，提供解决方案建议

### 系统管理
- 🌐 **多实例管理** - 同时管理多个 Zabbix 实例，统一运维平台
- 🔐 **权限控制** - 基于角色的访问控制（RBAC），细粒度权限管理
- ⚙️ **配置管理** - 数据库驱动的配置系统，支持运行时更新
- 📱 **菜单管理** - 动态菜单系统，基于角色的菜单权限控制
- 🔒 **安全加密** - 敏感信息自动加密存储

## 系统架构

![1](/zbxtable.png)

## 组件说明

**ZbxTable**: 后端使用 [Gin 框架](https://github.com/gin-gonic/gin) 和 Go 语言开发。

**ZbxTable-Web**: 前端使用 React 16、Ant Design 4、ECharts 和 G6 开发。官方前端的仪表盘、主机、告警、报表、拓扑和系统管理页面均保留；当前版本在官方前端上补充了 Zabbix 多实例接入和设备巡检页面。前端源码位于独立的 [ZbxTable-Web 仓库](https://github.com/canghai908/zbxtable-web)，发布构建后嵌入 Go 服务。

## 🛠️ 技术栈

### 后端技术
- **语言**: Go 1.24+
- **Web 框架**: Gin
- **ORM**: GORM
- **数据库**: MySQL 5.7+ / PostgreSQL 12+
- **AI 集成**: Ollama / Deepseek API

### 前端技术
- **框架**: React 16
- **UI 组件**: Ant Design 4
- **图表**: ECharts
- **拓扑图**: G6

### 告警接收
- **Webhook 方式**: ZbxTable 提供 Webhook API 接口，直接接收 Zabbix 告警
- **接口地址**: `http://your-zbxtable-server:8089/v1/receive`
- **认证方式**: Token 认证
- **支持格式**: JSON

在 Zabbix 中配置 Webhook 媒介类型，将告警发送到 ZbxTable 的 Webhook 接口即可实现告警接收和分发。详细配置请参考[官方文档](https://zbxtable.com)。

## 在线演示

[https://demo.zbxtable.com](https://demo.zbxtable.com)

**默认账号：** `admin / Zbxtable`

## 兼容性

| Zabbix 版本    | 兼容性 |
|:---------------|:------:|
| 7.4.x          |   ✅   |
| 7.2.x          |   ✅   |
| 7.0.x LTS      |   ✅   |
| 6.4.x          |   ✅   |
| 6.2.x          |   ✅   |
| 6.0.x LTS      |   ✅   |
| 5.4.x          |   ✅   |
| 5.2.x          |   ✅   |
| 5.0.x LTS      |   ✅   |
| 4.4.x          |   ✅   |
| 4.2.x          |   ✅   |
| 4.0.x LTS      |   ✅   |
| 3.4.x          | 未测试 |
| 3.2.x          | 未测试 |
| 3.0.x LTS      | 未测试 |

## ⚠️ 重要提示

**ZbxTable 3.0 与 2.x 版本数据库结构不兼容，建议全新安装。** 如果您正在使用 2.x 版本，请备份重要数据后重新安装 3.0 版本。

## 快速开始

### 方式一：一键安装脚本（推荐）

适用于 CentOS、Ubuntu、Debian 等 Linux 系统，自动完成所有配置。

```bash
# 交互式安装管理器：按菜单选择 systemd、Docker、更新、修复或卸载
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/install-release.sh | sudo bash
```

**安装脚本功能：**
- ✅ 自动检测操作系统类型
- ✅ 自动下载最新版本
- ✅ 创建系统用户和目录
- ✅ 配置 systemd 服务
- ✅ 配置防火墙规则
- ✅ 自动启动服务

**安装后访问：**
- 首次安装：`http://your-server-ip:8089`
- 默认账号：`admin / Zbxtable`（请立即修改密码）

### 方式二：源码包手动部署

#### 1. 下载并构建源码

从本仓库 GitHub Release 下载源码包和对应校验文件。也可以使用前文的一键安装管理器自动下载、校验并部署。手动构建需要 Go 1.24+ 和已构建的前端资源：

```bash
wget https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/zbxtable-v3.0.8-source.tar.gz
wget https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/zbxtable-v3.0.8-source.tar.gz.sha256
sha256sum -c zbxtable-v3.0.8-source.tar.gz.sha256
tar -xzf zbxtable-v3.0.8-source.tar.gz
cd zbxtable-v3.0.8
go build -trimpath -o zbxtable ./main.go
```

#### 2. 配置数据库

可以使用独立数据库，也可以与 Zabbix 共用 MySQL/MariaDB 或 PostgreSQL 数据库。共用数据库时使用具备创建和读写 `zbxtable_` 前缀表权限的账号；不要对 Zabbix 原生表执行迁移或删除操作。

**MySQL：**

```sql
CREATE DATABASE zbxtable CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'zbxtable'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON zbxtable.* TO 'zbxtable'@'localhost';
FLUSH PRIVILEGES;
```

**PostgreSQL：**

```sql
CREATE DATABASE zbxtable;
CREATE USER zbxtable WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE zbxtable TO zbxtable;
```

#### 3. 启动服务

**创建系统用户：**

```bash
# 创建 zbxtable 系统用户
sudo useradd -r -s /sbin/nologin zbxtable

# 创建安装目录
sudo mkdir -p /usr/local/zbxtable

# 复制二进制文件
sudo cp zbxtable /usr/local/zbxtable/

# 设置权限
sudo chown -R zbxtable:zbxtable /usr/local/zbxtable
sudo chmod +x /usr/local/zbxtable/zbxtable
```

**配置 systemd 服务：**

```bash
# 创建 systemd 服务文件
sudo tee /etc/systemd/system/zbxtable.service > /dev/null << EOF
[Unit]
Description=ZbxTable - Zabbix Monitoring Tool
After=network.target

[Service]
Type=simple
User=zbxtable
Group=zbxtable
WorkingDirectory=/usr/local/zbxtable
ExecStart=/usr/local/zbxtable/zbxtable web
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 重载 systemd
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start zbxtable

# 设置开机自启
sudo systemctl enable zbxtable

# 查看服务状态
sudo systemctl status zbxtable
```

#### 4. 访问安装向导

访问 `http://your-server-ip:8089`，按照安装向导配置数据库连接并完成安装。

## 📚 文档

- [官方功能保留与扩展说明](./docs/官方功能保留与扩展说明.md) - 以官方 v3.0.6 为基线说明原有功能、扩展功能和代码/界面对应关系
- [Zabbix 实例对接与排障](./docs/Zabbix实例对接与排障.md) - 多实例新增、连通性检查和常见问题
- [Zabbix 巡检与 Windows 日志对接指南](./docs/Zabbix-巡检与Windows日志对接指南.md) - 巡检、日志采集和通知
- [3.0.8 完整部署手册](./docs/3.0.8-完整部署手册.md) - Linux、Docker 和更新修复步骤
- [文档中心](./docs/README.md) - 全部现有说明和发布资料索引
- [API 文档](./docs/api/README.md) - API 接口概览
- [官方网站](https://zbxtable.com) - 更多文档和教程

## 📊 系统要求

### 最低配置

- **CPU**：2 核
- **内存**：4 GB
- **磁盘**：20 GB
- **操作系统**：CentOS 7/8、Ubuntu 18.04+、Debian 9+、RHEL 7/8

### 推荐配置

- **CPU**：4 核
- **内存**：8 GB
- **磁盘**：50 GB SSD
- **数据库**：MySQL 5.7+ 或 PostgreSQL 12+

### 网络要求

- 能够访问 Zabbix Server API
- 如使用邮件通知，需访问 SMTP 服务器
- 如使用企业微信，需访问企业微信 API
- 如使用 Deepseek API，需访问互联网

## 🔄 从 2.1 升级到 3.0

**⚠️ 重要：ZbxTable 3.0 与 2.x 版本数据库结构完全不兼容，无法直接升级。**

建议操作步骤：

1. **备份 2.x 版本的重要数据**（拓扑图、自定义配置等）
2. **全新安装 3.0 版本**（使用一键安装脚本或二进制部署）
3. **重新配置系统**（Zabbix 实例、告警规则等）

如果必须保留历史数据，请联系技术支持获取数据迁移方案。

## 🔒 安全建议

1. **修改默认密码** - 首次登录后立即修改 admin 密码
2. **使用 HTTPS** - 配置 Nginx 反向代理，启用 SSL 证书
3. **防火墙配置** - 仅开放必要端口，限制访问来源 IP
4. **定期备份** - 每天备份数据库和配置文件
5. **权限管理** - 使用最小权限原则，定期审查用户权限

## 📦 代码仓库

### 巡检、日志与共库部署

巡检支持 CPU、内存、磁盘、时间同步、异常 IP、异常账号、登录失败和暴力破解检测，周报/月报按设备输出平均值。与 Zabbix 共用数据库时，ZbxTable 表使用 `zbxtable_` 前缀并保持数据隔离；安装脚本不会停止或修改 Zabbix 服务。完整的 Windows/Linux 日志采集、中文 Zabbix 配置、邮件告警和故障排查步骤请参阅：[Zabbix 巡检与 Windows 日志对接指南](docs/Zabbix-巡检与Windows日志对接指南.md)。

**ZbxTable**: [https://github.com/canghai908/zbxtable](https://github.com/canghai908/zbxtable)

**ZbxTable-Web**: [https://github.com/canghai908/zbxtable-web](https://github.com/canghai908/zbxtable-web)

## 👥 开发团队

**后端开发**: [canghai908](https://github.com/canghai908)

**前端开发**: [ahyiru](https://github.com/ahyiru)

## 🤝 贡献

欢迎贡献代码！请随时提交 Pull Request。

## 📞 支持

- **GitHub Issues**: [https://github.com/canghai908/zbxtable/issues](https://github.com/canghai908/zbxtable/issues)
- **官方文档**: [https://zbxtable.com](https://zbxtable.com)
- **在线演示**: [https://demo.zbxtable.com](https://demo.zbxtable.com)

## 📱 关注我们

扫码关注微信公众号，获取最新动态、技术文章和使用技巧：

<div align="center">
  <img src="docs/wechat.png" alt="微信公众号" width="600"/>
  <p>微信扫一扫关注公众号</p>
</div>

## 📄 许可证

ZbxTable 使用 Apache-2.0 许可证。详见 [LICENSE](LICENSE) 文件。

---

**ZbxTable 3.0 - 让 Zabbix 监控更智能、更强大！** 🚀

## 自动打包、发布与安装

在 Windows PowerShell 运行 `scripts\publish-release.ps1 -Version v3.0.8`，或在 Linux 运行 `bash scripts/publish-release.sh`，脚本会检查必需文件并生成源码压缩包和 SHA256 校验文件。需要创建 GitHub Release 并上传时，先运行 `gh auth login`，再运行 `scripts\publish-release.ps1 -Version v3.0.8 -Upload` 或 `ZBXTABLE_VERSION=v3.0.8 bash scripts/publish-release.sh --upload`。上传需要显式指定参数。

发布完成后，`dist/zbxtable-v3.0.8/` 是可直接上传到 Linux 的完整目录，`source.tar.gz` 是推荐的 Linux 压缩包，`source.zip` 用于 Windows。Linux 首次部署可使用 `sudo bash install-release.sh --install-deps --install-root=/opt/zbxtable` 自动准备基础环境；卸载使用 `scripts/uninstall.sh`，彻底删除时增加 `--purge --yes`。

3.0.8 Linux 一行安装（环境检测、文件校验、安装、启动和状态输出）：

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/install-release.sh | sudo bash -s -- --version=v3.0.8 --install-deps --install-root=/opt/zbxtable
```

Docker 一键安装（自动检测 Docker、可选安装 Docker、构建前端镜像并检查网页）：

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/install-release.sh | sudo bash -s -- --version=v3.0.8 --docker-install --port=8089
```

已有安装需要升级时，使用 `--update`。脚本会自动识别 systemd 或 Docker，保留 `config/app.conf`，下载最新 Release、替换程序和前端、重启服务并执行网页健康检查：

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.sh \
  | sudo bash -s -- --update --install-root=/opt/zbxtable
```

自定义端口时把 `--port=8089` 改为例如 `--port=9088`，访问 `http://服务器IP:9088`。

如果服务器访问 Docker Hub 超时，可在菜单中填写可访问的 Go/Debian 镜像地址；命令行安装可使用 `--go-image`、`--runtime-image`、`--go-proxy` 和 `--go-download-base` 指定镜像源与 Go 下载地址。系统服务安装也支持 Go 代理参数。详见[网络受限环境部署说明](./docs/3.0.8-完整部署手册.md#网络受限时指定-go-代理和-docker-镜像)。

Release 发布后，可通过 `scripts/install-release.sh`（Linux）或 `scripts/install-release.ps1`（Windows）从 GitHub 下载并校验安装。完整命令、系统依赖、数据库共用说明和故障排查见[GitHub 上传、打包与一键安装指南](./docs/GitHub上传与发布指南.md)。

3.0.8 的完整部署、分别部署、升级回滚、巡检、日志告警和卸载步骤见 [3.0.8 完整部署手册](./docs/3.0.8-完整部署手册.md)。

安装后可使用 `scripts/uninstall.sh --purge --yes`（Linux）或 `scripts/uninstall.ps1 -Purge -Yes`（Windows）一键删除 ZbxTable；默认不使用 `--purge` 时会保留 `config/app.conf`。卸载不会停止 Zabbix，也不会删除共用数据库中的 Zabbix 原生数据。
