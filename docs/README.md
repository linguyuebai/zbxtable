# ZbxTable 文档中心

本文档按当前仓库实际存在的文件整理。v3.0.6 的官方主机、告警、拓扑、报表和系统管理能力仍是兼容基线；多实例 Zabbix 对接、巡检与安全日志检测作为扩展加入。数据库共用仅指共用 MySQL/PostgreSQL 服务，ZbxTable 自身表使用 `zbxtable_` 前缀，不改写 Zabbix 原生表。

## 官方功能与扩展

- [官方功能保留与扩展说明](./官方功能保留与扩展说明.md)：官方功能范围、接口兼容约定和发布检查。
- [Zabbix 实例对接与排障](./Zabbix实例对接与排障.md)：新增实例、连接测试、认证和接口排障。
- [巡检与 Windows 日志对接指南](./Zabbix-巡检与Windows日志对接指南.md)：设备指标、周/月报告、安全日志采集和告警流程。
- [API 文档](./api/README.md)：接口入口及认证方式。

后端路由由 [api/v1/router.go](../api/v1/router.go) 注册。官方主机、主机组、模板、监控项、历史趋势、图表、告警、拓扑、系统配置、设备类型/分组、出口配置、用户/用户组、菜单和报表接口均保留。新增功能采用独立的 `/v1/zabbix`、`/v1/inspection` 路由，或在现有页面路由中追加兼容接口；路由契约测试可防止后续修改误删入口。

## 部署与维护

- [官方模式：本地后端直部署](./官方模式-本地后端直部署.md)：使用 Go 后端内置前端，直接通过 systemd 启动并访问登录页。
- [3.0.8 完整部署手册](./3.0.8-完整部署手册.md)：Linux systemd、Docker、安装、修复、更新、卸载和排障。
- [3.0.7 完整部署手册](./3.0.7-完整部署手册.md)：历史版本部署参考。
- [Docker 部署指南](../deployments/docker/README.md)：容器构建和运行说明。
- [配置模板](../config/app.conf.example)：本地或服务端配置项；真实凭据只放在本机配置中。

## 开发与发布

- [贡献指南](../CONTRIBUTING.md)
- [GitHub 上传与发布指南](./GitHub上传与发布指南.md)
- 前端通过 `scripts/prepare-frontend.sh`、`scripts/prepare-frontend.ps1` 或 `scripts/prepare-frontend.bat` 构建并嵌入。
- 发布前执行 Go 测试、`go vet ./...`、前端构建、静态资源检查和 `git diff --check`。

旧版资料曾引用当前分支不存在的 `QUICKSTART.md`、`SYSTEM.md`、`CHANGELOG.md` 和 `config/app.conf`。请以根目录 README、上述实际存在的手册和当前 Release 内容为准。
