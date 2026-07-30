# Clear 权限与信任模型研究

- 状态：Wayfinder 研究结论
- 日期：2026-07-30
- 对应票据：[Maidang1/clear#6](https://github.com/Maidang1/clear/issues/6)
- 适用范围：macOS 14+、GitHub Releases、Apple Silicon 与 Intel

## 结论摘要

Clear 应采用以下权限与信任模型：

1. **继续把“不使用 Developer ID、用户手动信任”作为明确的分发约束，而不是安全能力。** 当前产物有 ad-hoc 完整性签名，但没有可验证开发者身份，也没有 Apple 公证。产品文案必须准确说明这一点，并提供 SHA-256 与 GitHub 构建来源核验；不能把 ad-hoc 签名称为“已认证”。
2. **当前版本保持非 App Sandbox 架构。** 跨应用诊断与清理是 Clear 的核心能力；如果未来启用 App Sandbox，应作为新的架构决策处理，而不是简单添加 entitlement。
3. **基础功能不得依赖 Full Disk Access。** 内存中心、运行应用排行、当前白名单缓存与旧日志扫描，应在用户没有授予 Full Disk Access 时继续工作。
4. **Full Disk Access 只是一项用户主动开启的增强能力。** 它用于用户明确选择的广域受保护数据扫描，不应在首次启动时请求，也不应成为“推荐设置”或健康分数扣分项。
5. **权限状态按“能力 + 具体资源”建模，不维护 `fullDiskAccessGranted` 之类的全局真值。** Clear 应通过即将执行的只读操作验证资源是否可访问，并把结果记录为“此资源本次可用”“此资源本次受限”或“尚未验证”。
6. **拒绝、撤销和无法判断都必须局部降级。** 扫描继续执行，受限位置被跳过并单独计数；任何结果都不能暗示“已扫描整个 Mac”。
7. **访问其他应用容器前必须提供 `NSAppDataUsageDescription`。** macOS 14+ 将其他应用的 sandbox container 作为受保护资源；说明文案只描述用户主动选择的本地扫描与预览，不能暗示后台持续访问。
8. **不引入 root Helper。** Full Disk Access、App Data、Files & Folders、App Management、普通文件权限、App Sandbox 和 SIP 是不同的安全层；root 不是绕过这些层的产品方案。
9. **Intel 与 Apple Silicon 使用同一能力模型。** 不按 CPU 架构判断权限；以运行时资源探测为准，并在两种硬件上分别验证授权、拒绝、撤销和升级行为。

## 当前工程事实

| 维度 | 当前状态 | 证据 |
| --- | --- | --- |
| 系统与语言 | Swift 6，最低 macOS 14 | [`Package.swift`](../../Package.swift) |
| 分发产物 | `arm64 + x86_64` Universal App | [`scripts/build_universal_app.sh`](../../scripts/build_universal_app.sh) |
| 签名 | `codesign --sign -` ad-hoc 签名，启用 hardened runtime；脚本明确说明它不识别开发者、不能绕过 Gatekeeper | [`scripts/build_universal_app.sh`](../../scripts/build_universal_app.sh) |
| 公证 | 不使用 Developer ID，不提交 Apple notarization | [`README.md`](../../README.md) |
| App Sandbox | 没有 entitlements 文件，也没有 `com.apple.security.app-sandbox` | [`scripts/build_universal_app.sh`](../../scripts/build_universal_app.sh)、[`Support/Info.plist`](../../Support/Info.plist) |
| 隐私说明 | `Info.plist` 目前没有 `NSAppDataUsageDescription` 或其他受保护资源说明 | [`Support/Info.plist`](../../Support/Info.plist) |
| 当前扫描范围 | 精确白名单中的应用缓存与旧诊断报告；不扫描 Mail、Messages、Safari、Application Support、Containers、其他用户或系统卷 | [`README.md`](../../README.md)、[`DefaultCleanRules.swift`](../../Sources/ClearCore/Cleaning/DefaultCleanRules.swift) |
| 当前降级能力 | 扫描和执行能把 `EACCES`、`EPERM`、`NSFileReadNoPermissionError` 映射为 permission denied，并继续汇总其他结果 | [`ScanCoordinator.swift`](../../Sources/ClearCore/Cleaning/ScanCoordinator.swift)、[`CleanupCoordinator.swift`](../../Sources/ClearCore/Cleaning/CleanupCoordinator.swift) |

这里有一个重要的术语修正：Clear 当前不是“完全未签名”，而是**没有开发者身份的 ad-hoc 签名**。ad-hoc 签名可以提供一次构建内部的代码完整性检查，但不能让 Gatekeeper 验证发布者身份。Apple 对 App Store 外分发的正式路径是 Developer ID 签名与 notarization；Gatekeeper 默认检查开发者身份、公证和代码是否被更改。[Apple Developer ID](https://developer.apple.com/developer-id/)；[Gatekeeper and runtime protection](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)

## 安全层必须彼此独立

Clear 不应把“权限”压缩成一个开关。一次文件操作至少同时受以下层次影响：

| 安全层 | 解决的问题 | Clear 可以做什么 | Clear 不能声称什么 |
| --- | --- | --- | --- |
| Gatekeeper 与 quarantine | 下载的软件是否可以首次启动 | 解释手动信任流程，提供校验信息 | 用户一定能绕过；受管理设备可以禁止 override |
| 代码身份与 notarization | 谁发布了软件、Apple 是否检查过已知恶意内容 | 准确说明当前没有 Developer ID/公证 | ad-hoc 签名等同于开发者认证 |
| App Sandbox | 进程被允许接触哪些系统资源 | 当前保持非 sandbox；未来单独决策 | 非 sandbox 等于全盘可访问 |
| TCC / Mandatory Access Control | 用户是否允许访问某类隐私资源 | 在用户触发具体能力时访问并处理系统结果 | Full Disk Access 是万能通行证 |
| POSIX 权限、ACL、文件锁与所有权 | 当前用户是否有读写权限 | 把访问失败映射到具体资源 | FDA 一定能覆盖普通文件权限 |
| SIP 与其他系统保护 | 系统关键区域和数据完整性 | 将这类位置标为不支持 | FDA 或管理员身份能安全绕过系统保护 |

Apple 说明，macOS 的 Files & Folders、Full Disk Access、Accessibility 与 Automation 都是独立的用户控制面；Full Disk Access 面向包括 Mail、Messages、Safari、Home、Time Machine 和部分管理设置在内的广域数据。[Change Privacy & Security settings on Mac](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)

SIP 也独立于用户身份和 App Sandbox。Apple 明确说明，SIP 的安全策略应用于所有进程，包括管理员进程和 sandboxed 进程。[System Integrity Protection](https://support.apple.com/guide/security/system-integrity-protection-secb7ea06b49/web)

因此：

- Full Disk Access 不等于 root。
- root 不等于绕过 TCC 或 SIP。
- 非 sandbox 不等于没有 TCC。
- 通过一次资源探测不等于其他路径也可访问。

## GitHub 分发与首次信任

### 用户可观察的事实

Gatekeeper 默认希望 App Store 外的软件由注册开发者签名并经过 Apple 公证。用户可以在未被设备管理策略禁止时主动 override，但这个动作是用户对风险的接受，不是 Clear 获得了 Apple 信任。[Gatekeeper and runtime protection](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)

Apple 当前给出的手动流程是：

1. 先尝试打开应用。
2. 打开“系统设置 → 隐私与安全性”。
3. 使用“仍要打开 / Open Anyway”并再次确认。

Apple 说明，“Open Anyway”通常只在尝试打开后的约一小时内出现；确认后该 App 会被保存为安全设置中的例外。[Safely open apps on your Mac](https://support.apple.com/en-us/102445)

### Clear 的安装体验要求

- Release 页面和 App 内“关于”页面统一使用：
  - “未使用 Developer ID”
  - “未经过 Apple 公证”
  - “包含 ad-hoc 完整性签名”
- 每个 DMG 发布：
  - SHA-256
  - 对应 Git commit
  - GitHub Actions build provenance
- 不建议用户：
  - 关闭 Gatekeeper
  - 关闭 SIP
  - 批量删除 quarantine 属性
  - 运行来源不明的安装脚本
- 更新后必须允许出现“需要再次信任或重新授权”的情况。由于当前没有 Developer ID 身份，产品不能承诺系统会把下一版识别成同一个受信任发布者。
- 受 MDM 管理的 Mac 可能禁止用户 override。Clear 应显示“此设备的安全策略不允许启动未认证应用”，而不是提供绕过步骤。

## macOS 14+ App Data 保护

`NSAppDataUsageDescription` 是 macOS 14+ 的 Info.plist key，用来向用户说明为什么应用需要访问其他应用 sandbox containers 中的文件。[NSAppDataUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappdatausagedescription)

对 Clear 的含义是：

- 当前白名单中的 `~/Library/Caches/<bundle-id>` 不应被自动等同为“其他应用容器”。
- 一旦磁盘清理或卸载残留功能要进入 `~/Library/Containers/<bundle-id>` 等其他应用容器，就必须：
  1. 先在产品中说明将扫描哪个应用、哪些位置、为什么；
  2. 由用户发起该次扫描；
  3. 提供本地化的 `NSAppDataUsageDescription`；
  4. 接受系统可能授权、拒绝或不提供访问；
  5. 只把实际读取成功的路径计入覆盖范围。
- Info.plist key 只是用途说明，不是提前授权，也不能保证某个路径一定可读。
- 不得通过预扫描所有容器来“探测权限”，因为这本身就是一次隐私资源访问。

建议的用途说明草案：

> Clear 仅在你主动选择扫描时读取其他应用的可再生缓存和残留，用于在本机生成清理预览；未经确认不会移动文件。

该文案需要随实际功能缩小或调整，不能在尚未支持“只读预览、用户确认、移入废纸篓”时提前加入。

## 权限状态：按资源实测，不做全局猜测

Apple 的受保护资源并不都提供类似相机或定位那样的公开 `authorizationStatus` API。Full Disk Access 的官方用户入口在 System Settings；Apple 的文档说明用户必须主动添加应用。[Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

Clear 不应：

- 读取或解析 TCC 数据库；
- 调用私有 API；
- 用一个著名路径的读写结果推断“已获得全盘权限”；
- 把文件不存在、普通 POSIX 权限、App 正在运行、路径已变化和 TCC 拒绝合并成同一种错误；
- 在设置页展示未经验证的“Full Disk Access：已开启”。

建议状态模型如下：

| 状态 | 含义 | UI 文案 |
| --- | --- | --- |
| 未请求 | 用户尚未启用相关高级能力，也未访问该资源 | “尚未检查” |
| 本次可访问 | 对目标资源的只读探测刚刚成功 | “此位置可扫描” |
| 本次受限 | 目标资源返回 `EACCES`、`EPERM`、`NSFileReadNoPermissionError` 或等价拒绝 | “此位置未授权” |
| 用户已拒绝 | Clear 在当前用户操作中收到明确拒绝，或用户选择不继续 | “已跳过” |
| 已撤销或已变化 | 过去成功，但执行前复验失败 | “访问已变化，请重新检查” |
| 不受支持 | 目标位于系统保护区、其他用户空间，或超出 Clear 的产品边界 | “Clear 不会处理此位置” |
| 失败但原因不明 | I/O、损坏、文件消失或无法分类的错误 | “无法读取；未计入扫描” |

“本次可访问”只描述被探测的资源和访问方式。它不是永久授权证明，也不是 Full Disk Access 的替代显示。

## 能力与降级矩阵

| 能力 | 基础模式（无 FDA） | 可选 Full Disk Access 的作用 | 授权或访问触发点 | 如何判断 | 拒绝或失败后的降级 |
| --- | --- | --- | --- | --- | --- |
| 启动 Clear | 需要用户对 GitHub 下载产物执行 Gatekeeper override | 无关 | 首次启动下载产物 | 系统是否允许启动 | 无法启动；展示官网/README 指引，不提供绕过安全策略的命令 |
| 系统内存状态 | 完整可用；不需要文件隐私权限 | 无关 | 打开内存中心或菜单栏监控 | Darwin API 实际返回值 | 单项采样失败则标为不可用，其余指标继续 |
| 运行应用排行与正常退出 | best effort；部分受保护进程可能不可读 | 无关 | 用户打开排行或执行退出 | 每个进程/API 的实际结果 | 隐藏或标注不可读取的进程；不显示为 0 B |
| 当前白名单缓存与旧日志 | 只扫描当前用户、明确规则且实际可读的位置 | 通常不需要 | 用户开始扫描 | 每个规则根与条目的只读访问结果 | 跳过受限规则/条目，显示“未扫描位置数”；其余候选有效 |
| 其他应用 sandbox container | macOS 14+ 可能要求 App Data 授权；必须有 `NSAppDataUsageDescription` | 可能扩大访问，但不能作为每个 container 的成功保证 | 用户为某个应用主动扫描残留 | 对该应用、该 container 的只读操作 | 只跳过该应用的 container 残留；仍展示可访问的 bundle、缓存和用户选择位置 |
| Desktop、Documents、Downloads、iCloud Drive、网络卷、移动卷 | 受 Files & Folders 等用户控制；不要后台遍历 | 不应为这些普通用户选择范围优先引导 FDA | 用户选择具体目录或开启对应扫描 | 目标目录的实际只读操作 | 提供选择其他位置、重试或跳过；不扩大到整个磁盘 |
| Mail、Messages、Safari、Home、Time Machine 与管理数据 | 默认不扫描 | 仅用户主动开启“高级受保护数据扫描”时使用 | 用户先阅读具体范围与风险，再进入 System Settings 授权 | 对所选能力的多个明确资源分别只读探测；结果仍按资源显示 | 该高级类别不可用；内存、普通清理、启动项与基础卸载不受影响 |
| 删除或更新其他 App bundle | 读取基本元数据通常可用；移动 App 可能触发独立的 App Management 控制和普通文件权限 | FDA 不是 App Management 的替代 | 用户选择一个 App 并确认卸载事务 | 对选定 bundle 的执行前复验和移动结果 | 保留分析结果，提供“在 Finder 中显示”；不自动升级权限或永久删除 |
| 启动项检查 | 只展示通过公开 API 或可访问配置得到的结果 | 不应以 FDA 承诺完整枚举 | 用户打开启动项模块 | 每个来源独立标注覆盖范围 | 无法读取的来源标为“未检查”；不声称“没有启动项” |
| 系统卷、SIP 区域、其他用户数据 | 不支持 | 仍不进入 Clear 1.0 清理范围 | 不触发 | 静态安全策略 + 执行前路径复验 | 显示“受系统保护 / 超出范围”；永不建议关闭 SIP 或修改所有权 |

Apple 说明，macOS 10.15+ 会对 Documents、Downloads、Desktop、iCloud Drive 和网络卷等位置实施用户同意控制；需要整个存储访问的应用必须由用户在系统隐私设置中明确添加。[Controlling app access to files in macOS](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web)

Apple 的 System Settings 说明还把 **App Management** 定义为“允许应用更新或删除其他应用”。因此，卸载模块必须把 App Management 作为独立能力处理，不能把它归入 Full Disk Access。[Change Privacy & Security settings on Mac](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)

## Full Disk Access 的产品规则

### 允许

- 仅在设置中的“高级扫描范围”明确启用。
- 在启用前列出：
  - 会新增哪些类别；
  - 会接触哪些代表性位置；
  - 读取目的；
  - 数据全部本地处理；
  - 关闭后哪些能力仍可用。
- 提供打开 Privacy & Security 的入口或清晰手动步骤。
- 用户返回 Clear 后，重新探测用户刚刚启用的具体能力。
- 执行清理前再次复验路径、文件身份、所属规则和权限。

### 禁止

- 首次启动立即引导 FDA。
- 用红色警告或健康扣分迫使用户授权。
- 宣称“授权后可以扫描整个 Mac”。
- 因为一个路径成功就显示全局“已授权”。
- 因为一个路径失败就断言 FDA 关闭。
- 反复触发系统提示。
- 将 FDA 与管理员密码、root、App Sandbox entitlement 混为一谈。
- 读取 TCC 数据库来同步 UI。

### System Settings 深链接

Apple 的用户文档提供 Privacy & Security 的标准导航路径，但没有把具体设置页 URL scheme 作为稳定的第三方 API 合同。Clear 可以把深链接作为便利入口，但必须始终保留文本步骤，并在链接失败时降级；不能依赖深链接判断授权完成。

## 非 Sandbox 与未来 Sandbox 边界

当前构建没有 App Sandbox entitlement，因此 Clear 是非 sandboxed App。这个选择符合 GitHub 分发与跨应用清理的现阶段需求，但不移除 TCC、POSIX、SIP 或 Data Vault 等保护。

如果未来启用 App Sandbox：

- 用户通过 `NSOpenPanel` / `NSSavePanel` 选择的文件访问是 Apple 公开支持的扩展 sandbox 范围方式；对应 entitlement 为 user-selected read-only/read-write。[Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)；[User Selected File Read/Write entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write)
- 需要跨启动保留用户选择时，必须设计 security-scoped bookmark 的生命周期。
- FDA 不能通过 entitlement 或代码自动获得；仍由用户在 System Settings 决定。[Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- App Sandbox 自身限制与 TCC 授权需要同时满足，不能把 FDA 当成 sandbox escape。
- 跨应用缓存、卸载残留和第三方启动项的产品范围都必须重新验证。

因此，“是否启用 App Sandbox”应记录为一次独立 ADR，而不是权限服务的实现细节。

## 拒绝与降级 UX

Clear 已确定的统一安全事务是：

> 预览 → 明确确认 → 执行前复验 → 操作 → 展示结果与恢复路径

权限 UX 应嵌入这个事务，而不是成为独立的 onboarding 闸门。

### 扫描前

- 基础扫描不展示授权弹窗。
- 用户首次进入高级类别时，用产品页面先解释范围；只有用户选择“继续”后才访问受保护资源。
- 一次只为当前用户意图所需的最小资源触发访问。

### 扫描中

- 权限失败不取消整个扫描。
- 每个规则或资源保留单独状态。
- 候选总数、大小和健康结论只基于已成功扫描的数据。
- 页面必须显示：
  - 已扫描范围；
  - 未扫描范围；
  - 跳过原因；
  - 对结果完整性的影响。

### 用户拒绝

- 本次立即停止访问该资源。
- 不在同一工作流里再次触发。
- 提供“保持基础模式”作为同等正常的选择。
- 设置页可以显示“高级能力未启用”，但不能显示错误徽标。

### 授权被撤销或执行前失败

- 停止受影响项目的写操作。
- 不把权限失败自动归类为“文件已被清理”。
- 保留其他项目的事务结果。
- 显示具体恢复动作：
  - 重新检查此位置；
  - 返回设置查看权限；
  - 跳过此类别；
  - 在 Finder 中显示目标。

### 不可判定

- 文案使用“Clear 当前无法读取此位置”，而不是“你没有授予 Full Disk Access”。
- 只有用户主动进入 FDA 指引时，才解释 FDA 可能是其中一个原因。

## 建议的技术边界

后续实现权限层时，应提供统一的 capability service，但不把业务错误抹平。

### 输入

- capability：内存观测、规则扫描、App Data、受保护数据、App Management 等；
- resource：规范化后的具体 URL、bundle identifier 或公开 API 来源；
- access kind：metadata、read、enumerate、trash/move；
- user intent：发起此次操作的页面和事务；
- observation time：探测或操作发生时间。

### 输出

- capability state；
- 已验证的具体范围；
- 原始错误类别；
- 是否可以重试；
- 是否应引导 System Settings；
- 降级后仍可用的能力；
- 用户可读的恢复建议。

### 不做

- 不缓存永久的 FDA 布尔值；
- 不读取系统隐私数据库；
- 不把 `FileManager.isReadableFile` 当作执行授权；
- 不在扫描阶段做写入测试；
- 不通过创建或删除探针文件验证读权限；
- 不绕过现有 `openat` / `fstatat` 路径复验；
- 不为权限失败引入 root Helper。

## Intel 与 Apple Silicon 一致性

TCC、Gatekeeper、App Sandbox、POSIX 权限和 SIP 的产品模型应由 macOS 版本与具体资源决定，而不是由 CPU 架构决定。Clear 当前已经生成单一 Universal App，并在 Apple Silicon 与 Intel GitHub Actions runner 上测试。[`scripts/build_universal_app.sh`](../../scripts/build_universal_app.sh)；[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)

实现要求：

- 同一 bundle identifier、Info.plist、entitlements 和权限文案用于两个 slice。
- 不出现 `#if arch(...)` 权限逻辑。
- 所有权限判断都通过同一运行时 capability service。
- 在真实 Intel 与 Apple Silicon 机器上分别测试，不能只依赖编译 CI。
- 测试结果按 OS 版本记录；如果两个架构表现不同，先视为实现或系统版本差异，而不是设计两个权限模型。

## 验证矩阵

Apple 提供 `tccutil` 相关测试指导与不同受保护资源的 reset 标识，适合开发测试环境；这些命令不应暴露为普通用户修复步骤。[Resetting access to protected resources in macOS](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos)

### 设备

- Apple Silicon：
  - macOS 14 最新补丁版
  - 当前最新支持版
- Intel：
  - macOS 14 最新补丁版
  - Intel 可运行的最新支持版
- 至少一台受 MDM 管理、禁止 Gatekeeper override 的测试设备或等价策略环境。

### 安装与身份

- 首次从 GitHub Release 下载，带 quarantine。
- “Open Anyway”成功。
- 用户取消信任。
- 受管理策略禁止 override。
- 从版本 N 更新到 N+1：
  - Gatekeeper 是否再次要求确认；
  - App Data / Files & Folders / FDA 是否保留；
  - 旧版本授权与新版本资源探测是否一致。
- SHA-256 与 GitHub provenance 核验。

### 每项资源权限

- 从未请求。
- 允许。
- 拒绝。
- 允许后在 System Settings 撤销。
- 目标不存在。
- 普通 POSIX/ACL 拒绝。
- TCC 拒绝。
- App 正在运行。
- 扫描后文件或祖先目录被替换。
- FDA 已开启但资源仍受 SIP/其他保护。

### 自动化范围

- 单元测试使用注入的 capability probe 和错误码覆盖状态转换。
- 集成测试验证“一个规则被拒绝时，其余规则继续”。
- UI 测试验证：
  - 结果不夸大覆盖范围；
  - 拒绝后不循环请求；
  - 关闭高级能力不产生错误态；
  - 执行前权限撤销会阻止写入。
- 交互式 TCC 与 Gatekeeper 测试使用干净 VM snapshot 或专用机器，不把共享 CI runner 的既有授权状态当成可靠证据。

## 对 Clear 1.0 的决策建议

1. 保持当前 GitHub Releases、ad-hoc 签名、无公证的约束，但把安装风险与校验路径写入主规格。
2. Clear 1.0 保持非 App Sandbox，记录未来变化必须走 ADR。
3. Full Disk Access 为可选高级能力；基础模式是完整、正常、长期支持的产品形态。
4. 先完成按资源 capability model，再扩展 Containers、受保护数据与完整卸载残留。
5. 在任何 other-app container 功能合入前添加并本地化 `NSAppDataUsageDescription`。
6. App Management 独立于 FDA，在卸载模块中单独原型验证和验收。
7. 不引入 root Helper，不提供绕过 Gatekeeper、TCC 或 SIP 的命令。
8. 内存、磁盘、启动项和卸载模块统一使用“无法确认就拒绝写入、继续提供可用的只读结果”的行为。

## 需要在模块票据中继续验证的事项

以下内容不改变本研究的权限模型，但需要在对应模块实现前做小型原型：

- macOS 14 与当前最新系统上，App Management 对“将第三方 App bundle 移入废纸篓”的实际触发条件、用途说明和撤销行为；
- ad-hoc 签名版本升级后，各类 TCC 决策的保留情况；
- macOS 14+ 不同类型 App container 的 prompt、拒绝和重新授权体验；
- System Settings 深链接在支持版本上的可用性，以及失败时的手动导航 fallback；
- 第三方启动项仅使用公开 API 时能覆盖到的来源边界。

这些原型的验收标准不是“找到绕过方式”，而是为能力矩阵补充真实的系统行为，并确保拒绝时能安全降级。

## Apple 一手资料

- [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)
- [Gatekeeper and runtime protection in macOS](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)
- [Safely open apps on your Mac](https://support.apple.com/en-us/102445)
- [Change Privacy & Security settings on Mac](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)
- [Controlling app access to files in macOS](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web)
- [NSAppDataUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappdatausagedescription)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [User Selected File Read/Write entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write)
- [Resetting access to protected resources in macOS](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos)
- [System Integrity Protection](https://support.apple.com/guide/security/system-integrity-protection-secb7ea06b49/web)
