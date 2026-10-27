# Zabbix 实例对接与排障

本文说明 ZbxTable 的 Zabbix 实例连接方式、管理入口和接口，可用于首次安装配置和连接故障排查。

## 对接工作方式

ZbxTable 与 Zabbix 使用两类连接：

1. ZbxTable 的业务数据库连接保存在 `config/app.conf`。可以与 Zabbix 共用 MySQL/MariaDB 服务和数据库，但建议创建独立的 ZbxTable 数据表前缀/账号权限；安装器不会停止或重配 Zabbix 服务。
2. ZbxTable 从服务端通过 Zabbix HTTP API 读取监控数据。浏览器不直接连接 Zabbix API，所以应在运行 ZbxTable 的服务器上验证 DNS、路由、防火墙和反向代理访问。

新增实例后，配置存储在 ZbxTable 的实例配置表中；每个实例单独保存 Web/API 地址和加密后的密码或 API Token。API 连接会按实例 ID 缓存；编辑地址、凭据、启停或删除实例时会清理对应连接缓存。

## 界面配置步骤

1. 登录 ZbxTable，打开“系统管理 → Zabbix 对接”。
2. 选择“新增对接”，填写唯一实例标识、显示名称及 Zabbix Web/API 地址。
3. 地址可填写站点根地址，如 `https://monitor.example.com/zabbix`，也可填写完整 API 地址，如 `https://monitor.example.com/zabbix/api_jsonrpc.php`。不要填写登录页、查询参数或带用户名密码的 URL。
4. 选择用户名密码或 API Token。推荐在 Zabbix 中为 ZbxTable 建立专用的只读用户/API Token，并按需授予目标主机、主机组和历史数据读取权限。
5. 点击“测试连接”。确认版本和连接状态后保存。保存时会再次检测，若检测失败，配置仍会保存并在列表显示错误原因，便于修正后再次测试。
6. 在列表可测试、编辑、启停或删除实例。编辑时密码和 Token 不会回显；留空表示沿用已保存凭据。切换认证方式时，旧凭据会被清除，避免继续使用旧 Token。

## API 接口

以下接口需要先登录 ZbxTable，并通过 `X-Token` 请求头携带登录令牌。接口前缀为 `/v1`：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `GET` | `/v1/zabbix/instance` | 查询实例列表，响应不包含密码和 Token |
| `GET` | `/v1/zabbix/instance/:id` | 查询单个实例供编辑，敏感凭据为空字符串 |
| `POST` | `/v1/zabbix/instance/test` | 保存前测试地址和认证信息；编辑现有实例可传 `id` 并省略凭据以复用已保存凭据 |
| `POST` | `/v1/zabbix/instance` | 新增实例 |
| `POST` | `/v1/zabbix/instance/:id/test` | 重测已保存实例 |
| `PUT` | `/v1/zabbix/instance/:id` | 更新实例 |
| `PUT` | `/v1/zabbix/instance/:id/enabled` | 启用或停用实例，JSON 如 `{"enabled":true}` |
| `DELETE` | `/v1/zabbix/instance/:id` | 删除实例配置和连接缓存，不会删除 Zabbix 服务或 Zabbix 数据库 |

新增请求示例（密码认证）：

```json
{
  "instance": "prod-zabbix",
  "name": "生产监控",
  "url": "https://monitor.example.com/zabbix/api_jsonrpc.php",
  "auth_type": "password",
  "user": "zbxtable-reader",
  "pass": "替换为实际密码",
  "enabled": true,
  "notify_method": "webhook"
}
```

Token 认证将 `auth_type` 改为 `token`，并填写 `token`。编辑时传入的空密码/Token 表示保留原值；切换认证方式时服务端会清理不再使用的认证凭据。

## 服务端连通性检查

在 ZbxTable 服务器上对目标 URL 的 `/api_jsonrpc.php` 发起 JSON-RPC POST。不要用浏览器 GET 是否返回 412 来判断连接可用性：版本、代理和 WAF 配置会导致 GET 返回 404、405、412 等状态，但 JSON-RPC POST 仍然可以正常工作。

```bash
curl -sS -X POST 'https://monitor.example.com/zabbix/api_jsonrpc.php' \
  -H 'Content-Type: application/json-rpc' \
  --data '{"jsonrpc":"2.0","method":"APIInfo.version","params":{},"id":1}'
```

期望响应的 `result` 是版本号，例如 `7.4.0`。该请求只验证网络和 API 地址，不验证账号或 Token。最终凭据验证应使用 ZbxTable 页面上的“测试连接”。Token 测试会调用 `host.get`，因此该 Token 必须至少具有 ZbxTable 实际读取目标主机所需的读取权限。

## 常见问题

- **连接超时 / connection refused**：在 ZbxTable 主机检查 DNS、路由、服务器防火墙、代理和 Zabbix Web 服务状态；确认目标站点从服务器侧可访问。
- **404**：检查 URL 中是否包含 Zabbix 实际部署子路径（常见为 `/zabbix`），以及反向代理是否转发了 `/api_jsonrpc.php`。
- **401、Not authorized 或 Token validation failed**：重新生成 Token，确认 Token 未过期且具备 API 访问和主机读取权限。密码认证请检查账号、密码和 Zabbix 用户状态。
- **测试通过但页面数据为空**：确认该实例已启用；检查账号对目标主机/主机组的可见权限、主机是否受监控，以及页面是否筛选了错误的实例。
- **刚修改认证后仍读取失败**：确认列表测试状态和错误消息；服务端已经清除实例对应的 API 缓存。如仍异常，查看 ZbxTable 应用日志并重新执行“测试连接”。
- **安装后看不到对接入口**：刷新页面或清除旧的浏览器缓存后重新登录；运行旧二进制的服务需要重新构建/安装包含新前端资源和新接口代码的版本。

## 凭据与恢复注意事项

ZbxTable 不会把密码或 Token 返回给浏览器。加密密钥由当前应用配置生成，因此迁移数据库或恢复备份时应一并保留原 ZbxTable 配置/加密密钥，否则旧凭据无法解密，需要重新填写 Zabbix 认证信息。不要将含真实凭据的接口请求、日志或配置文件提交到公开仓库。
