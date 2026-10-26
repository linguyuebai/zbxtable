# ZbxTable 巡检与 Zabbix 日志告警对接指南

本文适用于 Zabbix 5.0 及以上、ZbxTable 3.0。ZbxTable 可以与现有 Zabbix 共用同一个 MySQL/MariaDB 或 PostgreSQL 数据库；应用自己的表统一使用 `zbxtable_` 前缀，不写入 Zabbix 的 `hosts`、`items`、`history`、`events` 等原生表，也不会停止或修改 Zabbix 服务。

## 1. 安装与共存

在 ZbxTable 目录执行一键脚本。脚本会检查 Go、数据库连通性、端口和写权限；Linux 脚本支持 Ubuntu、Debian、CentOS、Rocky Linux、AlmaLinux，Windows 使用 PowerShell 脚本。

```bash
chmod +x scripts/install.sh scripts/run.sh
./scripts/install.sh
./scripts/run.sh
```

Windows 管理员 PowerShell：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1
.\scripts\run.ps1
```

安装脚本只创建 `zbxtable` systemd 服务（Windows 创建独立进程/服务脚本），不会执行 `systemctl stop zabbix-server`、不会覆盖 Zabbix 配置。首次启动前填写与 Zabbix 相同的数据库地址、端口、库名、账号和密码。建议为 ZbxTable 建立独立数据库账号，并只授予该库所需权限；共用数据库时至少限制来源地址和密码权限。

## 2. 数据隔离与巡检策略

启动后在中文界面进入“报表/设备巡检”，新增策略并选择 Zabbix 实例、主机或主机组。默认采集：IP、主机名、CPU、内存总量/使用率、磁盘使用率/剩余容量、时间偏差、登录失败、暴力破解、异常来源 IP 和异常账号。

允许 IP 填写登录来源地址或 CIDR，例如 `10.10.0.0/16,192.168.1.20`；允许账号填写 `Administrator,root`。未列出的账号会写入结果和告警详情。所有百分比和报表数值按两位小数展示。日报保留明细，周报/月报按设备和指标输出平均值，不展示每天的数值。

巡检接口：

* `GET /v1/inspection/policies/:id/results`：分页明细，可用 `status=warning` 筛选异常。
* `GET /v1/inspection/policies/:id/summary`：汇总设备数、正常/异常数、CPU/内存/磁盘平均值、最近检查时间和常见异常原因；可用 RFC3339 的 `start`、`end` 限定周报/月报范围。
* `POST /v1/inspection/export`：生成“巡检汇总”和“巡检明细”两个工作表，可直接用于汇报。

定时任务默认每 10 分钟运行，可在“系统配置”调整 `inspection_enabled=1` 和 `inspection_cron`。异常会进入 ZbxTable 告警，并沿用已配置的通知渠道；同一主机相同巡检异常在 30 分钟内去重。

## 3. Windows 日志采集

在 Windows 安装 Zabbix Agent 2，以管理员身份编辑 `zabbix_agent2.conf`，加入事件日志监控项：

```text
Plugins.WindowsEventlog.Log.Security	type=eventlog	logfile=Security	severity=warning,error	mode=all
```

也可以在 Zabbix 中文界面为 Windows 主机创建类型为“Zabbix agent (active)”的监控项，键值使用 `eventlog[Security,,,,4624|4625|4648|4672|4720|4740,,skip]`，信息类型选择“日志”。为暴力破解单独创建过滤项，例如 `eventlog[Security,,,,4625,,skip]`。将对应 item key 填入巡检策略的“登录日志 item key”和“暴破日志 item key”。

常用 Windows Security 事件：

| 事件 ID | 含义 |
| --- | --- |
| 4624 | 登录成功 |
| 4625 | 登录失败 |
| 4648 | 使用显式凭据登录 |
| 4672 | 特殊权限登录 |
| 4720 | 创建用户 |
| 4740 | 账号锁定 |

事件日志中 `Account Name`、`TargetUserName`、`IpAddress` 会分别用于异常账号和异常 IP 检测。建议先在 Windows 审核策略中启用“登录/注销”和“账户管理”成功、失败审核。

## 4. Linux 日志采集

Ubuntu/Debian 常用 `/var/log/auth.log`，RHEL 系列常用 `/var/log/secure`。在 Zabbix 中文界面创建日志监控项：

```text
log[/var/log/auth.log,Failed password|authentication failure|Accepted password,,,skip]
```

把该键填入登录日志项；暴力破解项可以使用 `log[/var/log/auth.log,Failed password,,,skip]`。确保 `zabbix` 用户有读取日志的权限（加入 `adm` 或日志专用组），并在 Agent 配置中允许主动检查。不要把日志内容写入 ZbxTable 自己的数据库表，巡检只读取 Zabbix API 返回的历史数据。

## 5. 中文 Zabbix 页面、API 和邮件告警

1. 在 Zabbix 中文界面进入“用户设置/ API 令牌”，为只读巡检账号创建 Token；在 ZbxTable“Zabbix 实例”中填写 API 地址、Token，并测试连接。
2. 进入“配置 → 主机 → 监控项”，按上面的 Windows/Linux 键值创建日志项，等待产生历史数据后再执行一次巡检。
3. 进入“管理 → 报警 → 媒体类型”，新增“Email”，填写 SMTP 主机、端口、加密方式、发件账号和授权码；在“用户 → 媒体”中填写收件人。
4. 在“动作”中创建触发器动作，条件可使用事件名称包含“登录失败”“暴力破解”“时间同步”或严重性为“警告及以上”，操作选择发送 Email。ZbxTable 产生的巡检异常会调用同一告警通知渠道。
5. 用“测试”发送一封邮件，再在巡检策略中点“立即巡检”。检查 `/v1/inspection/policies/:id/results?status=warning` 和“监控 → 告警”是否出现记录。

## 6. 故障排查

* 没有日志：确认 Agent 2 已重启、主机可用、item key 拼写正确，并在 Zabbix“监测 → 最新数据”查看值。
* 时间同步异常：确认 `system.localtime` 存在；Windows 可改用返回 Unix 时间戳的自定义 item。策略中的时间偏差阈值单位为秒。
* 邮件未发送：先在 Zabbix 媒体类型执行测试，再检查用户媒体、动作时间段和 SMTP 防火墙。
* 共用数据库失败：检查数据库账号权限、字符集和端口；确认没有把 Zabbix 的库名误填到其他实例。ZbxTable 只会自动迁移 `zbxtable_` 前缀表。
* 安装脚本报端口占用：修改 ZbxTable 的监听端口，不要停止 Zabbix Server、Proxy 或 Agent；两个服务可以在同一台服务器上并行运行。
