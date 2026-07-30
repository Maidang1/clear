# macOS 14+ 应用资产归属与安全排除研究

- 日期：2026-07-31
- 对应决策票：[研究应用资产归属、容器边界与安全排除](https://github.com/Maidang1/clear/issues/18)
- 范围：Clear 1.0 的应用 bundle、缓存、日志、偏好、Application Support、容器、共享容器、插件和安装收据

## 结论

公开文件系统约定可以证明“某个路径看起来由某个 bundle identifier 命名”，但不能普遍证明其中内容都是可删除的。Apple 明确说明 Application Support 可以包含用户数据；沙盒容器和 App Group 容器也可能保存应用或多个应用共享的私有数据。因此 Clear 1.0 必须把“身份归属”和“删除资格”分开。

Clear 1.0 的保守边界是：

1. 用户明确选择的普通第三方 `.app` bundle 可以作为卸载主目标；
2. 与完整 bundle ID 精确匹配的 Caches 和 Logs 可作为可再生附属候选；
3. Preferences 只作为默认不选的“会丢失设置”候选；
4. Application Support、沙盒容器、App Group、用户文档、外部插件和共享数据不进入 1.0 自动候选；
5. Full Disk Access、App Data 或 App Management 只改变能力，不改变归属和安全结论；
6. 应用本体和每个附属项目分别进入统一安全事务，任何不确定结果立即停止扩大。

## Apple 平台事实

### Bundle 身份

Apple 将 `CFBundleIdentifier` 定义为在系统中唯一标识一个 bundle 的字符串，但它是 bundle 声明，不是对任意同名磁盘目录的所有权证明。[CFBundleIdentifier](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier)

代码签名的 designated requirement 用于判断两个版本是否应视为同一代码；典型要求结合签名者与 identifier。[Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)；[Understanding the Code Signature](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/AboutCS/AboutCS.html)

因此：

- bundle ID 是必要身份字段，但单独不足以证明任意旁路文件属于该应用；
- 可用时应记录签名 designated requirement、Team ID 和签名有效性；
- 未签名或签名无效的第三方应用仍可由用户明确选择卸载，但其附属资产归属需要更保守；
- Clear 自身的 ad-hoc 签名不能获得与第三方应用“同团队”的权限或信任捷径。

### 标准目录不是同一种数据

Apple 的文件系统指南把 Application Support 描述为应用管理的支持文件，并明确说明它可以包含用户数据；按惯例应用会使用 bundle ID 命名子目录。[macOS Library Directory Details](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html)

同一指南说明沙盒 Mac 应用的 Application Support、Cache、临时目录和其他相关数据位于系统定义的容器中。[File System Basics](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)

由此得到：

- `~/Library/Caches/<bundle-id>` 可以支持“可再生缓存”的强归属；
- `~/Library/Logs/<bundle-id>` 可以支持“应用日志”的强归属；
- `~/Library/Preferences/<bundle-id>.plist` 可以支持“应用设置”的强归属，但设置本身不是垃圾；
- `~/Library/Application Support/<bundle-id>` 只支持应用相关性，不能支持可删除性；
- 目录名、文件名前缀或厂商名相似不能建立安全归属。

### 容器与共享容器

macOS 14+ 在应用尝试读取其他应用沙盒容器文件时使用 `NSAppDataUsageDescription` 向用户解释访问原因；该键是用途说明，不是授权保证。[NSAppDataUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappdatausagedescription)

App Group 容器用于多个应用之间共享数据，Foundation 返回的标准位置是 `~/Library/Group Containers/<group-id>`。[containerURL(forSecurityApplicationGroupIdentifier:)](https://developer.apple.com/documentation/foundation/filemanager/containerurl%28forsecurityapplicationgroupidentifier%3A%29)；[Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)

Apple 在 macOS 15+ 进一步为 App Group 本地文件提供系统保护，即使应用本身没有 App Sandbox。[Accessing app group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

因此 Clear 1.0：

- 不把 `~/Library/Containers/<bundle-id>` 作为卸载候选；
- 不把 `~/Library/Group Containers` 中任何内容作为候选；
- 不通过扫描容器来探测权限；
- 即使用户授予访问，也只把它表达为数据覆盖能力，不改变默认排除。

### 插件与共享代码

Apple bundle 结构中的 `Contents/PlugIns` 是主应用 bundle 的内嵌组成部分，随整个 `.app` 一起移动。[Bundle Structures](https://developer.apple.com/go/?id=bundle-structure)

外部 loadable bundles、frameworks 和系统插件目录可能被宿主或多个应用使用；bundle 本身只说明可加载代码的结构，不提供第三方卸载器可依赖的所有者关系。[About Loadable Bundles](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingCode/Concepts/AboutLoadableBundles.html)；[About Bundles](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/AboutBundles/AboutBundles.html)

因此：

- `.app/Contents` 内嵌插件与应用本体一起移动；
- 应用 bundle 外的 Audio Unit、Quick Look、Internet Plug-In、framework、driver、system extension 或其他插件不进入 1.0 自动候选；
- 仅凭 bundle ID 前缀、Team ID 或厂商名相同不能删除外部插件。

### 权限彼此独立

Apple 的隐私设置把 App Management 定义为允许应用更新或删除其他应用；Full Disk Access 则用于访问其他应用数据、备份和部分管理数据。两者不是同一能力。[Change Privacy & Security settings](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)

App Sandbox、TCC、POSIX 权限、App Management 和 SIP 都可能独立阻止访问。Clear 必须按具体 app bundle 和具体附属根做真实复验，不能维护一个全局“可卸载”或“FDA 已开启”布尔值。

## 归属与候选等级

| 等级 | 证据 | Clear 1.0 行为 |
| --- | --- | --- |
| `selectedAppBundle` | 用户明确选择；位于 `/Applications` 或 `~/Applications`；有效 `.app` 结构；冻结文件/卷身份、bundle ID、可执行文件和签名证据 | 应用本体默认选中；系统/Apple 应用、Clear 自身、其他用户或外部卷排除 |
| `strongRegenerable` | 精确 `~/Library/Caches/<bundle-id>` 或 `~/Library/Logs/<bundle-id>`；应用身份匹配；普通文件满足安全规则 | 作为可展开附属候选；默认可选中，说明重建或日志丢失影响 |
| `appSpecificSensitive` | 精确 Preferences 文件或明确 app-specific 状态 | 默认不选；单独说明会重置设置；必须再次显式选择 |
| `relatedButUserBearing` | Application Support、Saved Application State、容器或可能包含用户内容的位置 | 只显示“已排除/请人工检查”，不提供移动操作 |
| `sharedOrAmbiguous` | App Group、共享父目录、外部插件、厂商前缀、Team ID 相同、安装收据或名称匹配 | 永不进入候选 |
| `blocked` | 权限、保护、I/O、损坏或身份无法复验 | 显示受阻范围，不猜测内容 |

安装收据、Spotlight 元数据和代码签名可以作为解释应用来源的证据，但不能单独生成删除列表。一个 package 可能安装共享组件或被多个产品引用，收据也不能证明文件当前仍属于唯一应用。

## 永久排除

- `/System/Applications`、`/System/Library`、Apple 系统组件和 Clear 自身；
- 其他用户目录、外部卷、网络卷和任意用户输入目录；
- Documents、Desktop、Downloads、Movies、Music、Pictures、iCloud/Mobile Documents；
- `~/Library/Application Support` 下任何内容；
- `~/Library/Containers`、`~/Library/Group Containers`、Application Scripts；
- 浏览器 profile、邮件、消息、照片、钥匙串、数据库和用户工程；
- 外部插件、framework、driver、system extension、LaunchAgent/Daemon；
- 仅由名称、厂商前缀、Team ID、收据或时间推测出的路径；
- 厂商卸载脚本和 shell 命令的自动执行。

## 数据完整性

每个候选根独立保存：

- 身份证据；
- 最近观测与新鲜度；
- 可读/可移动能力；
- 归属等级；
- 排除原因；
- 权限或保护缺口。

未访问容器、Application Support 和共享数据是设计性排除，不是健康缺陷。权限阻止已允许范围时为 `partial`；应用本体身份无法建立时为 `unavailable`，不能创建卸载事务。

## Intel 与 Apple Silicon

文件归属、权限和安全事务语义不按 CPU 架构分叉。Mach-O 架构可以解释应用是否能在当前 Mac 原生运行或需要 Rosetta，但不能提高删除资格。

Universal、仅 Intel、仅 Apple Silicon 和脚本型应用都使用同一候选等级。Release 必须在原生 Intel 与 Apple Silicon 机器分别验证：

- bundle 身份与 package 移动；
- 运行应用复验；
- App Management/FDA/App Data 拒绝；
- 部分完成、不确定结果和废纸篓恢复；
- ad-hoc Clear 更新后权限可能重置。

## Clear 1.0 建议

1. 应用清单只枚举 `/Applications` 与 `~/Applications` 的普通第三方 `.app`，排除系统、Clear、自身和外部卷。
2. 用户选择应用后才扫描精确 Caches、Logs 和 Preferences 证据；不预扫所有容器。
3. 应用本体默认选择；强归属缓存/日志可默认选择；Preferences 默认关闭；Application Support、容器和共享项目只显示排除。
4. `.app` 是一个 package 事务项，必须用专门的 bundle mover 原子移入废纸篓；不能复用只处理普通叶子文件的磁盘清理适配器。
5. 附属缓存/日志仍按普通文件逐项处理；不为了“清干净”移动整个未知目录。
6. 应用必须先由用户正常退出并重新扫描；不 force terminate。
7. 执行前分别复验 app bundle 与附属项目。App Management、FDA 和普通文件权限按具体目标处理。
8. 结果按项目展示；应用已移动但某附属项失败属于部分完成，不能回滚伪装成原子卸载。
9. 任一项目为 `uncertain` 后停止尚未开始的移动。恢复依赖废纸篓位置或重新安装，不自动运行脚本。

这条边界牺牲“扫描全部残留”的表面完整性，但能兑现 Clear 的核心承诺：只处理可证明目标，默认排除可能承载用户或共享数据的范围。
