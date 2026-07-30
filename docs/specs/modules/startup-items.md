# Clear 1.0 启动项规格

- 状态：决策完成
- 地图：[Clear 1.0 启动项管理：决策地图](https://github.com/Maidang1/clear/issues/14)
- 研究：`docs/research/2026-07-31-startup-item-capabilities.md`
- 依赖：ADR 0002、ADR 0003

## 用户结果

用户能盘点 Clear 可读取的第三方 launchd 启动声明，理解来源、目标、触发条件、配置问题和数据缺口；需要改变第三方 Open at Login 或后台活动时，Clear 打开 Apple 系统设置，不假装能够“一键禁用所有启动项”。

## 发现边界

按顺序只读枚举：

1. `~/Library/LaunchAgents`
2. `/Library/LaunchAgents`
3. `/Library/LaunchDaemons`，默认折叠并标为系统级

`/System/Library` 不生成用户诊断发现，只在脱敏诊断导出中提供范围计数。

每个 plist 只使用 `PropertyListSerialization` 解析，不执行目标，不载入或卸载 job。快照包含来源 URL/范围、文件身份、Label、Program/ProgramArguments、触发摘要、内容摘要、所有权、目标解析、Mach-O 架构、解析问题和观测时间。

启动声明只表达 `present`、`invalid`、`unreadable`、`targetMissing` 等事实。它不包含第三方通用 `enabled` 布尔值，不用进程存在推断启用，也不测量或估算启动耗时。

## 诊断

Clear 1.0 的启动项模块不产生 `actNow`，也不做恶意软件判断。

- `review`：
  - 当前用户或第三方全局声明无法解析；
  - 声明目标缺失或解析歧义；
  - 同一作用域存在冲突 Label；
  - 目标 Mach-O 明确不支持当前 Mac 架构。
- `observe`：
  - 有效第三方声明及其 `RunAtLoad`、`KeepAlive`、定时、路径或 socket 触发；
  - 没有发现异常，但仍存在 Open at Login/BTM 数据缺口。
- `undetermined`：声明目录全部不可读、扫描中断或超过资源预算。

未签名、未知 Team ID、长期存在、`KeepAlive` 或高频定时不能单独升级为风险。架构兼容性只解释可能无法启动，不代表应该禁用。

零声明时文案为“在已覆盖的 launchd 声明目录中未发现第三方项目”，不能写“没有启动项”或 `clear`。

## 数据完整性

模块始终显示：“Open at Login 与 App Background Activity 的完整状态需在系统设置确认。”

- `coveredDeclarations`：三个第三方声明目录均完成，只表示静态声明覆盖；投影到健康概览时仍为 `partial`。
- `partial`：至少一个目录或项目受权限、I/O 或解析预算影响。
- `stale`：扫描超过 24 小时，或文件事件已标记目录变脏。
- `unavailable`：没有完成任何第三方声明目录。

BTM 私有数据不可见不是用户错误，也不以红色权限告警呈现。

## 信息架构

页面分为：

- 当前用户 LaunchAgents；
- 所有用户 LaunchAgents；
- 第三方系统服务声明；
- “系统设置中的登录项与后台活动”数据缺口。

条目显示 Label、目标、来源、触发摘要、所有者、架构证据和配置问题。允许在 Finder 中显示声明、复制脱敏诊断，不提供第三方开关。

页面唯一主操作是“打开登录项设置”，调用 `SMAppService.openSystemSettingsLoginItems()`。

## 系统设置交接

交接前显示：

- Clear 能观察到的声明证据；
- Clear 无法公开读取的 Open at Login/BTM 范围；
- 用户将在 Apple 设置中完成开关；
- 返回 Clear 后仍只能重新扫描静态声明，不能验证 BTM 开关结果。

打开系统设置本身没有副作用，不创建安全事务，也不记为“禁用成功”。返回后页面刷新时间和声明证据，但继续要求用户以系统设置为准。

## Clear 自有服务

只有 Clear bundle 中有已知标识的 `SMAppService` 可以读取精确 status 并执行 `register()` / `unregister()`。这条能力默认关闭，直到实际 GitHub ad-hoc Release 在 Intel 与 Apple Silicon 上通过：

- 注册、`requiresApproval`、启用、注销；
- 重启、App 移动、版本升级和再次信任；
- 用户拒绝与外部状态变化。

开启后，自有服务变更使用统一安全事务：预览精确服务和预期状态、复验当前 status、调用 API、重新读取 status，并提供相反操作作为恢复路径。

## 明确禁止

- 解析 BTM 私有数据库或依赖 `sfltool` 输出；
- 使用 Endpoint Security；
- 请求 Automation、Accessibility、管理员权限或 root Helper；
- UI scripting 系统设置；
- 调用 `launchctl` 修改第三方条目；
- 修改或删除第三方 plist、全局 daemon 或系统项；
- 自动禁用。

## 资源、历史与验收

- 单个 plist 最大读取 1 MiB；单次最多 2,000 个声明；解析在 utility QoS、最多 2 路并发且可取消。
- FSEvents 只标记快照过期，页面打开或用户刷新时重扫；不在事件回调中执行控制。
- 历史只保存模块摘要、配置问题计数和覆盖，不保存完整 ProgramArguments 或行为轨迹。
- 测试覆盖三类目录、损坏/超大 plist、缺失/脚本目标、冲突 Label、thin/fat Mach-O、权限、预算和零结果文案。
- Intel 与 Apple Silicon 使用同一状态和关注级别，只允许架构兼容性证据不同。
