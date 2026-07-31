# macOS 14+ 启动项能力边界研究

- 日期：2026-07-31
- 目标系统：macOS 14 及以上
- 目标版本：Clear 1.0
- 分发约束：GitHub 直接分发；不依赖 Developer ID 签名、Apple 公证或 MDM
- 研究范围：Open at Login、App Background Activity、LaunchAgents、LaunchDaemons、`SMAppService`、Background Task Management（BTM）及相关权限

## 结论

Clear 1.0 不能通过一个公开、稳定、面向普通桌面应用的 Apple API，完整枚举并直接开关“系统设置 > 通用 > 登录项与扩展”中的所有第三方项目。

可稳定交付的边界应当是：

1. **声明级发现**：读取当前用户和全局的 `launchd` plist，解释来源、目标程序、触发条件、文件所有权和可读性，但不把“存在 plist”说成“已启用”，也不把“没有 PID”说成“已停用”。Apple 说明用户代理来自 `/System/Library/LaunchAgents`、`/Library/LaunchAgents` 和用户的 `Library/LaunchAgents`；代理可能按需启动，因此是否正在运行不是启用状态的可靠替代。[Apple：Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
2. **Clear 自有服务的精确状态**：只有 Clear 自己包内、由 `SMAppService` 建模的服务才能使用 `status`、`register()` 和 `unregister()` 形成受支持的精确控制闭环。Apple 将该 API 描述为“注册和控制应用自己的 LoginItems、LaunchAgents 和 LaunchDaemons”，并明确这些 helper 位于应用主 bundle 内。[Apple：SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)；[Apple：Manage login items and background tasks](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)
3. **第三方登录项和 BTM 项目的用户交接**：Clear 展示可解释证据并通过 `SMAppService.openSystemSettingsLoginItems()` 打开系统登录项面板，让用户在 Apple 提供的界面中完成开关。[Apple：openSystemSettingsLoginItems()](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems%28%29)；[Apple：Change Login Items & Extensions settings](https://support.apple.com/guide/mac-help/change-login-items-extensions-settings-mtusr003/mac)
4. **不解析 BTM 私有存储或 `sfltool dumpbtm` 输出**：Apple 把 `sfltool` 放在测试、诊断和反馈流程中，没有为其输出声明可供应用依赖的稳定 schema；BTM 的归因资源本身位于 `PrivateFrameworks`。因此它只能作为人工诊断工具，不能作为 Clear 1.0 的产品数据源。[Apple：Manage login items and background tasks](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)
5. **不采用 Endpoint Security 监听 BTM**：Endpoint Security 虽提供 BTM add/remove 事件，但客户端需要 Apple 批准的受限 entitlement 和用户授予 Full Disk Access；这与 Clear 1.0 的无 Developer ID 分发边界不兼容，而且事件流也不是当前状态快照。[Apple：`es_event_btm_launch_item_add_t`](https://developer.apple.com/documentation/endpointsecurity/es_event_btm_launch_item_add_t)；[Apple：Endpoint Security entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client)；[Apple：`es_new_client`](https://developer.apple.com/documentation/endpointsecurity/es_new_client%28_%3A_%3A%29)

因此，Clear 1.0 的启动项模块应当被定义为“**可解释的启动声明盘点 + Apple 设置入口**”，而不是“所有启动项的一键禁用器”。对第三方项目的直接禁用/重新启用只有在后续专项验证出一个同时满足公开契约、可恢复和双架构测试的路径后才能加入。

## Apple 的对象并不是同一类东西

| 用户看到或工程中常用的名称 | 实际含义 | Clear 能否视为同一状态源 |
| --- | --- | --- |
| Open at Login | 用户登录时打开的 app、文档、文件夹或服务器连接。用户可在系统设置中添加和移除。[Apple 用户指南](https://support.apple.com/guide/mac-help/open-items-automatically-when-you-log-in-mh15189/mac) | 否。它不是所有后台 helper 的总表。 |
| App Background Activity | 系统设置中允许 app 在主 app 未打开时执行任务的用户控制面。[Apple 用户指南](https://support.apple.com/guide/mac-help/change-login-items-extensions-settings-mtusr003/mac) | 否。它是 BTM 呈现的一部分，不等于磁盘上的所有 plist。 |
| LaunchAgent | 在登录用户会话中由 `launchd` 管理的进程；可按需、定时或常驻启动。[Apple：Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) | 只能从 plist 得到“声明”，不能仅凭 plist 得到完整有效状态。 |
| LaunchDaemon | 系统级 `launchd` 服务；通常位于 `/System/Library/LaunchDaemons` 或 `/Library/LaunchDaemons`。[Apple：Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) | Clear 1.0 仅只读盘点第三方全局声明，不执行变更。 |
| `SMAppService` | app 为自己主 bundle 内的主 app 登录项、helper app、agent 或 daemon 创建的服务对象。[Apple：SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) | 只有服务所有者知道 bundle 内标识并具有受支持的 register/unregister 闭环。 |
| BTM | macOS 13+ 对登录项和后台任务提供归因、通知、用户批准和设备管理可见性的系统机制。[Apple 部署指南](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web) | 普通本地 app 没有公开的全量快照 API。 |
| MDM 后台任务状态 | macOS 14+ 的 declarative status report，可返回类型、状态、bundle ID、UID、label 和 Team ID。[Apple：Declarative status reports](https://support.apple.com/guide/deployment/declarative-status-reports-depd90ee8a5f/web) | 否。它由设备管理服务订阅，不是 Clear 这种本地普通 app 的 API。 |

## Clear 1.0 能力矩阵

“直接控制”只表示 Apple 文档给出了适合该对象的公开控制闭环；“交接”表示 Clear 只生成事务预览并打开系统设置，不伪装成已经完成操作。

| 对象范围 | 发现 | 可表达状态 | 禁用 | 重新启用 / 恢复 | Clear 1.0 决定 |
| --- | --- | --- | --- | --- | --- |
| Clear 主 app 自启动 | 已知自己的 bundle，可构造 `SMAppService.mainApp`。[Apple：mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) | `notRegistered`、`enabled`、`requiresApproval`、`notFound`；其中 `enabled` 只表示已注册且有资格运行，不表示当前有进程。[Apple：Status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum)；[Apple：enabled](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/enabled) | `unregister()`，系统不再启动该服务。[Apple：unregister](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister%28%29) | `register()`，仍受用户批准约束。[Apple：register](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29) | **条件支持**。Apple sample 要求配置 Team ID；Apple 文档没有承诺无稳定 Developer ID 身份的发布包可形成可靠注册身份，因此必须在 Clear 的实际无 Developer ID 构建上通过真机发布门槛后才能开启。[Apple sample 配置说明](https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api) |
| Clear bundle 内 helper LoginItem / LaunchAgent | 已知 helper bundle ID 或 plist 名称，可使用 `loginItem(identifier:)` / `agent(plistName:)`。[Apple：loginItem](https://developer.apple.com/documentation/servicemanagement/smappservice/loginitem%28identifier%3A%29)；[Apple：agent](https://developer.apple.com/documentation/servicemanagement/smappservice/agent%28plistname%3A%29) | 同上，精确到 Clear 自己建模的服务。`requiresApproval` 必须显示为“等待用户在系统设置批准”，不能显示为失败。[Apple：requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval) | `unregister()` | `register()` | **条件支持**，同样受无 Developer ID 发布包的真机验证门槛约束。 |
| 第三方 Open at Login 项目 | 当前公开的 `LSSharedFileList` 登录项 API 已被 Apple 列为 deprecated；系统设置仍能显示和管理 app、文档、文件夹及连接。[Apple：Deprecated Launch Services symbols](https://developer.apple.com/documentation/coreservices/launch_services/deprecated_symbols)；[Apple 用户指南](https://support.apple.com/guide/mac-help/change-login-items-extensions-settings-mtusr003/mac) | Clear 没有受支持的本地全量状态 API。 | 不直接控制；打开系统登录项面板。 | 不直接控制；用户在系统面板恢复。 | **交接**。数据完整性必须显示“系统设置中可能还有未被 Clear 盘点的 Open at Login 项目”。 |
| 第三方 `SMAppService` / App Background Activity 项目 | Apple 为管理员提供系统设置、MDM status report 和 `sfltool` 诊断；没有为普通 app 提供全量本地枚举 API。[Apple 部署指南](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web) | Clear 不应从 BTM 私有数据推导状态。 | 不直接控制；打开系统登录项面板。 | 不直接控制；用户在系统面板恢复。 | **交接**。可以解释“该 app 可能拥有后台活动”，但不得把未观测到等同于不存在。 |
| `~/Library/LaunchAgents/*.plist` | 读取当前用户可读 plist；提取 `Label`、程序/参数、`RunAtLoad`、`KeepAlive`、定时/路径触发和来源文件。Apple 确认这是 per-user agent 的标准目录。[Apple：Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) | 只表达 `declared`、`invalidDeclaration`、`targetMissing`、`scopeBlocked`；不表达 `enabled` 或 `running`。按需 job 没有 PID 仍可能处于正常可启动状态。 | 1.0 不直接控制。Apple 确认 `launchctl` 用于 load/unload，但没有给普通 app 一个跨第三方项目的事务 API。[Apple：Script management with launchd](https://support.apple.com/guide/terminal/script-management-with-launchd-apdc6c1077b-5d5d-4d35-9c19-60f2397b2369/mac) | 1.0 不承诺自动恢复；显示文件位置和系统设置入口。 | **只读发现**。把基于 `launchctl bootout/disable/enable/bootstrap` 的方案留给后续双架构、跨重启专项验证，不进入当前发布契约。 |
| `/Library/LaunchAgents/*.plist` | 只读盘点第三方全局用户代理。[Apple：Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) | 与用户 LaunchAgent 相同，只表达声明和观测限制。 | 不直接控制。全局 agent 文件应由 root 拥有；变更意味着扩展到管理员权限和全局用户影响。[Apple：launchd job ownership](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) | 不直接控制。 | **只读发现**。 |
| `/Library/LaunchDaemons/*.plist` | 只读盘点第三方系统服务声明。 | 仅声明级信息；不把进程匹配当成完整状态。 | 不直接控制。 | 不直接控制。 | **只读发现，默认折叠并标注“系统级”**。 |
| `/System/Library/LaunchAgents` 和 `/System/Library/LaunchDaemons` | 可用于解释 Apple 系统来源，但条目数量大且不是用户清理目标。 | 只读。 | 永不控制。SIP 限制包括 root 在内的进程修改 `/System` 等受保护位置。[Apple：About System Integrity Protection](https://support.apple.com/en-us/102149) | 不适用。 | **默认排除出诊断发现**；仅在开发者诊断导出中计数。 |
| BTM 数据库、`attributions.plist`、`sfltool dumpbtm` | `sfltool dumpbtm` 可打印当前登录和后台项，Apple 要求在测试/反馈中使用；归因文件在 `PrivateFrameworks`。[Apple 部署指南](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web) | 输出 schema 没有公开稳定契约。 | `sfltool resetbtm` 是重置测试数据，不是禁用单个启动项的产品 API。 | 不适用。 | **禁止作为产品数据源或操作路径**。 |
| Endpoint Security 的 BTM add/remove 事件 | 能观察 BTM 添加/移除事件，但不是安装后全量快照。[Apple：BTM add event](https://developer.apple.com/documentation/endpointsecurity/es_event_btm_launch_item_add_t) | 事件级，不是用户批准/启用状态的完整替代。 | 不提供禁用 API。 | 不提供恢复 API。 | **排除**。需要 Apple 批准的受限 entitlement 和 Full Disk Access，不符合 Clear 1.0 分发方式。[Apple：entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client)；[Apple：Monitoring System Events](https://developer.apple.com/documentation/endpointsecurity/monitoring-system-events-with-endpoint-security) |
| MDM 管理的登录/后台项目 | MDM 可按 bundle ID、Team ID、label 等规则自动批准项目；macOS 14+ 可向设备管理服务报告详细状态。[Apple：Managed Login Items payload](https://support.apple.com/guide/deployment/managed-login-items-payload-settings-dep07b92494/web)；[Apple：Declarative status reports](https://support.apple.com/guide/deployment/declarative-status-reports-depd90ee8a5f/web) | Clear 不是 MDM 服务，不能消费该报告作为本地 API。 | 不尝试覆盖组织策略。 | 不尝试覆盖组织策略。 | **显示“可能受组织管理”，交接系统设置/管理员**。 |

## 状态语义

### `SMAppService` 状态

仅对 Clear 自有、由 Clear 持有正确服务标识的对象使用以下状态：

| API 状态 | Clear 文案 | 禁止的推断 |
| --- | --- | --- |
| `enabled` | “已注册，可由系统启动” | 不能说“正在运行”。Apple 的定义是 successfully registered and eligible to run。[Apple：enabled](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/enabled) |
| `requiresApproval` | “已注册，等待你在系统设置中批准” | 不能当成注册失败。[Apple：requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval) |
| `notRegistered` | “未注册” | 不能外推第三方服务已关闭。[Apple：notRegistered](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/notregistered) |
| `notFound` | “在当前 app 包中未找到对应服务” | 不能显示为“已禁用”。[Apple：Status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum) |

`SMAppService.statusForLegacyPlist(at:)` 的文档上下文是让尚未迁移到新 bundle 结构的 app 检查**自己旧版 helper** 的授权状态，不应被扩展成第三方全量扫描器。[Apple：Updating helper executables](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)；[Apple：statusForLegacyPlist](https://developer.apple.com/documentation/servicemanagement/smappservice/statusforlegacyplist%28at%3A%29)

### 原始 `launchd` plist 状态

Clear 只记录以下互相独立的事实：

- `declaration`: `present` / `invalid` / `unreadable`
- `target`: `resolved` / `missing` / `ambiguous`
- `scope`: `currentUser` / `allUsers` / `system`
- `triggerSummary`: 从 plist 中解释出的 `RunAtLoad`、`KeepAlive`、interval、calendar、path、socket 等声明
- `observedProcess`: 仅作为“扫描当时观察到可能匹配的进程”的证据，不参与 enabled/disabled 判断
- `observedAt`: 时间戳

原因是 `launchd` 支持按需启动、常驻、时间触发和其他触发；job 当前没有运行并不表示已禁用，当前正在运行也不证明下一次登录仍会注册。[Apple：Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

## 发现流程和数据完整性

### 扫描顺序

1. 枚举 `~/Library/LaunchAgents`。
2. 枚举 `/Library/LaunchAgents`。
3. 枚举 `/Library/LaunchDaemons`，只读并默认折叠。
4. 不把 `/System/Library` 项目生成用户诊断发现；只在诊断导出中提供范围计数。
5. 对每个可读 plist 使用 `PropertyListSerialization` 解析，不执行其中的程序，不载入 job。
6. 解析目标时保留原始 `Program` / `ProgramArguments` 和解析结果；不猜测 shell 展开。
7. 对解析出的 app 或 executable 读取普通文件元数据、bundle 元数据和 Mach-O 架构；任何读取失败都成为该条目的 `scopeBlocked`，不升级权限。
8. 扫描结果始终附带一个不可消除的数据缺口：**“Open at Login 与 BTM 全量状态需在系统设置确认”**。

### 模块数据完整性

| 条件 | 数据完整性 |
| --- | --- |
| 三个第三方声明目录均完成枚举，所有发现的 plist 均可解析或有明确错误 | `coveredDeclarations`，文案：“已覆盖可读的用户与第三方 launchd 声明；系统登录项仍需在系统设置确认。” |
| 某个目录因 POSIX/TCC/IO 错误不可读 | `partial`，列出具体受阻目录和错误类别。 |
| 扫描被取消或超过资源预算 | `staleOrInterrupted`，保留上次聚合摘要但不复用上次目标清单。 |
| 只观察到零个 plist | 仍不能写“没有启动项”；应写“在已覆盖的 launchd 声明目录中未发现第三方项目”。 |

Apple 的系统设置才是用户可见的 Open at Login 和 App Background Activity 控制面；Apple 还明确把 MDM status report、系统设置和 `sfltool` 列为不同的识别路径。这证明任何单一非 MDM 本地来源都不应被标成完整 BTM 快照。[Apple：Manage login items and background tasks](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)

## 禁用、启用与恢复边界

### Clear 1.0 允许

- 对通过真机发布门槛的 **Clear 自有** `SMAppService` 执行 `register()` / `unregister()`。
- 对第三方项目生成事务预览，包含来源、证据、预期影响、当前数据缺口和“打开系统设置”这一个安全下一步。
- 调用 `SMAppService.openSystemSettingsLoginItems()`，由用户在 Apple 界面中完成第三方项目的切换。
- 复验时重新扫描声明文件，并要求用户确认系统设置中的结果；Clear 只报告自己能重新观察到的证据。

### Clear 1.0 禁止

- 不调用某个第三方 app 的 `SMAppService` `register()` / `unregister()`；该 API 的公开模型是 app 控制自己 bundle 内的服务。
- 不解析、修改或删除 BTM 私有数据库。
- 不把 `sfltool resetbtm` 当作清理动作；Apple 将它描述为测试之间重置登录和后台项目数据，并建议之后重启。[Apple 部署指南](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web)
- 不通过 UI scripting 点击系统设置。Accessibility 权限会允许第三方 app 控制 Mac，超出了启动项模块的必要权限。[Apple：Allow accessibility apps](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)
- 不通过 AppleScript / System Events 做默认发现或删除。控制其他 app 会进入 Automation 隐私边界；Clear 没有必要为了盘点启动声明请求它。[Apple：Allow apps to control other apps](https://support.apple.com/guide/mac-help/allow-apps-to-control-other-apps-on-mac-mchl07817563/mac)
- 不修改 `/System/Library`。
- 不在 1.0 中对 `~/Library/LaunchAgents` 承诺基于 `launchctl` 的持久禁用/恢复。Apple 公开说明 `launchctl` 用于 load/unload，但要形成 Clear 的安全事务，还需验证禁用状态跨登录/重启的持久性、BTM 同步、外部更新漂移和恢复语义。[Apple：Script management with launchd](https://support.apple.com/guide/terminal/script-management-with-launchd-apdc6c1077b-5d5d-4d35-9c19-60f2397b2369/mac)

### 后续如要加入直接 LaunchAgent 控制，必须先通过的专项门槛

这不是 Clear 1.0 当前能力，而是后续 research/prototype ticket 的验收清单：

1. 在 macOS 14 最新补丁的 Intel 与 Apple Silicon 真机上验证 `launchctl` 当前命令的退出码、stderr 和重启后状态。
2. 验证按需 job、`KeepAlive` job、定时 job、已运行 job、目标缺失、plist 语法错误和同 label 冲突。
3. 验证用户在系统设置同时切换、第三方 app 自动修复/升级 plist、注销登录、重启和 Clear 崩溃恢复。
4. 证明禁用不会删除供应商文件，不会让 BTM 与 launchd 状态出现无法解释的分叉。
5. 为重新启用提供可执行恢复路径，并用 plist URL、文件资源标识、`Label`、内容 hash 和目标 executable 身份做复验。
6. 任一状态无法可靠证明时返回“不确定结果”，停止扩大事务。

## 权限与隐私边界

| 能力 | 默认是否请求权限 | 理由 |
| --- | --- | --- |
| 读取标准 LaunchAgents / LaunchDaemons 声明目录 | 不预先请求 Full Disk Access | 先按当前进程权限尝试只读；失败即降低数据完整性。Apple 将 Full Disk Access 定义为访问其他 app 数据、备份和部分管理设置的广泛权限，不应把它当成普通声明盘点的默认前提。[Apple：Privacy & Security settings](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac) |
| 打开系统登录项设置 | 无额外隐私权限 | 使用 `SMAppService.openSystemSettingsLoginItems()`。[Apple 文档](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems%28%29) |
| AppleScript / System Events | 不请求 Automation | Automation 允许 app 访问和控制其他 app；不是只读 LaunchAgent 盘点的必要条件。[Apple 用户指南](https://support.apple.com/guide/mac-help/allow-apps-to-control-other-apps-on-mac-mchl07817563/mac) |
| UI scripting 系统设置 | 不请求 Accessibility | 该权限允许第三方 app 通过辅助功能控制 Mac，风险与收益不相称。[Apple 用户指南](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac) |
| Endpoint Security BTM 事件 | 不申请 | entitlement 必须向 Apple 申请，且 ES client 需要 Full Disk Access；与无 Developer ID 的 Clear 1.0 不兼容。[Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client)；[Apple：`es_new_client`](https://developer.apple.com/documentation/endpointsecurity/es_new_client%28_%3A_%3A%29) |
| 修改全局 agent/daemon | 不请求管理员权限 | 影响所有用户且需要扩展特权架构；Clear 1.0 只读。Apple 要求全局 agent/daemon 由 root 拥有。[Apple：Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) |
| 修改 Apple 系统项 | 永不请求 | SIP 保护系统位置，且系统项不属于用户清理目标。[Apple：About SIP](https://support.apple.com/en-us/102149) |

## Intel 与 Apple Silicon

研究到的公开 ServiceManagement、BTM 呈现、系统设置和 `launchd` 目录契约都按 macOS 版本声明可用性，没有按 Intel/Apple Silicon 分裂的控制 API。因此 Clear 应使用**同一套发现和状态语义**，不要为处理器架构创建两套产品行为。

真正的差异位于被启动 executable 的可运行架构：

- universal binary 可在 Intel 和 Apple Silicon 原生运行；
- 仅 `x86_64` 的 app 在 Apple Silicon 上需要 Rosetta；
- Apple Silicon 在首次运行 Intel app 且尚未安装 Rosetta 时会要求用户安装。[Apple：Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)；[Apple：Using Intel-based apps on Apple silicon](https://support.apple.com/en-us/102527)

Clear 1.0 因此可以把 Mach-O 架构作为一条**兼容性证据**：

| 当前 Mac | 目标 executable | Clear 文案 |
| --- | --- | --- |
| Intel | 包含 `x86_64` | “与此 Mac 架构兼容” |
| Intel | 仅 `arm64` | “目标程序不支持此 Intel Mac”；仍不自动禁用 |
| Apple Silicon | 包含 `arm64` | “可原生运行” |
| Apple Silicon | 仅 `x86_64` | “需要 Rosetta；是否已安装需另行观察” |
| 任意 | 脚本、缺失、格式未知 | “无法从文件格式确定架构兼容性” |

架构不参与“值得禁用”的判断；它只解释目标为何可能无法启动。Clear 自身的 GitHub 构建仍应输出 universal `arm64 + x86_64`，Apple 将 universal binary 定义为同时原生支持两类 Mac 的方式。[Apple：Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)

## Clear 1.0 工程接口建议

这些是根据上述 Apple 契约得出的产品/工程建议，不是 Apple API 的原文。

### `StartupDeclaration`

- `sourceURL`
- `sourceScope`: current user / all users / Apple system
- `fileResourceIdentifier`
- `label`
- `programReference`
- `resolvedProgramURL`
- `triggerSummary`
- `declarationHash`
- `ownership`
- `architectureEvidence`
- `parseIssues`
- `observedAt`

### `StartupObservation`

- `declarationState`
- `targetState`
- `observedProcessEvidence`
- `dataCompleteness`
- `blockedReason`
- `systemSettingsVerificationRequired`

刻意不提供第三方通用 `enabled: Bool`。只有 `OwnedSMAppServiceObservation` 可以保存 Apple 返回的 `SMAppService.Status`。

### 诊断发现规则

- “目标缺失但仍有有效 plist”可以成为诊断发现，因为它有直接可观察证据。
- “声明解析失败”可以成为低关注发现，并明确无法判断实际影响。
- `KeepAlive`、`RunAtLoad`、高频定时触发只能描述潜在启动行为，不能单独包装成风险。
- 未签名、未知 Team ID、仅 Intel 或长期存在不能单独包装成恶意或高风险。
- MDM/系统来源、权限受阻和 BTM 不可见性属于数据完整性，不降低健康状态。

## 发布门槛

启动项模块在 Clear 1.0 可标记完成前，至少需要：

1. macOS 14 Intel 与 Apple Silicon 真机的只读扫描夹具。
2. 对三类目录范围、损坏 plist、缺失目标、脚本目标、Mach-O thin/fat 和权限拒绝的确定性测试。
3. 证明扫描不会执行、load、unload 或修改任何第三方条目。
4. 证明零发现时仍显示 BTM/Open at Login 数据缺口。
5. 证明系统设置入口在 macOS 14+ 正确打开。
6. 若启用 Clear 自有 `SMAppService`，必须用实际 GitHub 发布产物分别验证注册、等待批准、注销、重启、应用移动/更新和取消注册；在无稳定 Developer ID 身份的产物上未通过时，功能保持关闭。
7. Intel/Apple Silicon 的同一测试断言只允许架构兼容性证据不同，状态和安全事务语义不得分叉。

## 最终建议

Clear 1.0 采用以下明确产品承诺：

> Clear 盘点并解释可读的第三方 `launchd` 启动声明，指出目标缺失、无效配置、作用范围和架构兼容性；对于 Apple 维护的 Open at Login 与后台活动状态，Clear 明确数据缺口并把用户带到系统设置完成确认和切换。Clear 不解析 BTM 私有数据，不申请 Endpoint Security、Automation 或 Accessibility 权限，也不在 1.0 中直接改写第三方启动项。

这条边界牺牲了“一键禁用所有启动项”的表面完整性，但符合 Clear 已建立的安全事务、复验、不确定结果、恢复路径和数据完整性语义。
