# macOS 14+ 内存观测、应用归属与数据质量边界

日期：2026-07-31
对应决策票：[#16 定义内存观测、应用归属与数据质量边界](https://github.com/Maidang1/clear/issues/16)

## 结论

Clear 1.0 可以在不获取其他进程 task port、不安装 root Helper 的前提下，可靠采集物理内存总量、系统 VM 页计数、压缩器占用页和交换空间，并监听系统内存压力的变化事件。它不能在“只使用 Apple 承诺的公开接口”这一约束下可靠获得其他应用的 physical footprint，更不能可靠汇总一个应用及其全部 helper、XPC service、WebContent 和被重新托管进程的“应用族总内存”。

因此，Clear 1.0 应：

1. 保留系统级内存观测，但把每个来源的覆盖、时间和失败原因独立记录；
2. 将压力变化事件与 Clear 自己从 VM 计数得出的估算严格分开，不能声称复刻 Activity Monitor；
3. 只把 `NSWorkspace` 发现的普通 GUI 应用作为“可请求正常退出的应用”，不展示或按内存占用排序；
4. 不做应用族内存聚合，不把 bundle ID 前缀、父子 PID 或可执行文件路径当成可靠所有权；
5. 在 Intel 与 Apple Silicon 上使用运行时页大小，并分别做原生架构验收。

## 1. 系统级可观测信号

| 信号 | 接口与已知语义 | Clear 1.0 边界 |
|---|---|---|
| 物理内存总量 | `ProcessInfo.processInfo.physicalMemory` 返回电脑的物理内存字节数。[Apple 文档](https://developer.apple.com/documentation/foundation/processinfo/physicalmemory) | 可作为独立、稳定来源。值为 `0` 时视为该来源失败，不能据此生成比例。 |
| 运行时页大小 | `host_page_size` 是 macOS 公开的 Mach 接口。[Apple 文档](https://developer.apple.com/documentation/kernel/1502512-host_page_size) | 每次进程生命周期至少成功读取一次；禁止硬编码 4 KiB 或 16 KiB。 |
| VM 页计数 | `host_statistics64(..., HOST_VM_INFO64, ...)` 对应公开的 `vm_statistics64_data_t`。[Apple 文档](https://developer.apple.com/documentation/kernel/vm_statistics64_data_t)；[XNU `HOST_VM_INFO64` 定义](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/host_info.h) | 可读取 free、active、inactive、wired、purgeable、file-backed、anonymous、compressor 等系统汇总页计数；必须验证返回码和返回字段数量，再用运行时页大小做溢出安全的字节换算。 |
| 压缩器物理占用 | XNU 把 `compressor_page_count` 定义为“压缩分页器用于容纳全部压缩数据的页数”，而 `total_uncompressed_pages_in_compressor` 是压缩器内数据解压后的页数。[XNU `vm_statistics64`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/vm_statistics.h) | 当前 `compressor_page_count × pageSize` 应命名为“压缩器占用”，不能描述成被压缩数据的原始总量；两个计数不能混用。 |
| 交换空间 | XNU 的公开 `xsw_usage` 结构给出 total、available、used 和 page size；内核的只读 `vm.swapusage` 实现令 `used = total - available`。[XNU 结构](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/sysctl.h)；[XNU 实现](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_sysctl.c) | `sysctlbyname("vm.swapusage", ...)` 可作为独立可选来源；失败只降低交换空间覆盖，不抹掉同一时刻的 VM 样本。 |
| 内存压力变化 | `DispatchSourceMemoryPressure` 监控系统内存压力条件的变化，事件为 normal、warning、critical。[Apple 文档](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure)；[事件含义](https://developer.apple.com/documentation/dispatch/dispatchsource/memorypressureevent/normal) | 这是变化通知，不是文档化的同步“当前压力查询”。启动后收到首个事件前应为 `notYetObserved`；收到后记录级别和事件时间。 |

### 不能直接相加的 VM 计数

XNU 明确说明 `speculative_count` 已包含在 `free_count` 中。[XNU `vm_statistics64`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/vm_statistics.h) 因而当前实现把 `free + inactive + speculative` 作为可回收量，会重复计算 speculative 页。后续实现必须至少改为不重复相加；而且 inactive、purgeable、file-backed 等队列也不应未经证据就全部称为“立即可回收”。

`pageins`、compressions、decompressions、swapins 和 swapouts 在 XNU 结构中标为 lifetime 计数。[同一 XNU 定义](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/vm_statistics.h) 它们适合在两次有效样本间计算增量，不适合直接显示成当前占用。计数回退、重启或任一端样本不完整时，不生成增量。

### “内存压力”与 Clear 估算

Apple 公开接口给出了压力变化事件和 VM 原始计数，但没有公开 Activity Monitor 的聚合公式。因此：

- Dispatch 事件可命名为“系统压力事件”；
- VM 计数派生值只能命名为“Clear 估算”，并保留公式版本；
- 首个压力事件到来前，系统压力状态为未知；不能用估算冒充系统事件；
- 估算不应仅因历史 swap 仍大就声称当前处于临界压力。

这项区分延续了现有代码注释中的正确意图，但需要修复 speculative 重复计算，并在模型中保存来源而不只保存一个合并枚举。

## 2. 其他应用进程的公开接口边界

### 可以可靠做到

`NSWorkspace.runningApplications` 是返回当前运行应用的公开 AppKit 接口。[Apple 文档](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications) `NSRunningApplication` 公开提供 PID；bundle ID 在应用没有 `Info.plist` 时可以为 `nil`，bundle URL 在进程没有 bundle 结构时也可以为 `nil`，launch date 只对 LaunchServices 启动的应用可用。[PID](https://developer.apple.com/documentation/appkit/nsrunningapplication/processidentifier)；[bundle ID](https://developer.apple.com/documentation/appkit/nsrunningapplication/bundleidentifier)；[bundle URL](https://developer.apple.com/documentation/appkit/nsrunningapplication/bundleurl)；[launch date](https://developer.apple.com/documentation/appkit/nsrunningapplication/launchdate)

Clear 因而可以建立普通 GUI 应用的短期快照，并通过公开的 `terminate()` 尝试正常退出；该方法本身只表示请求是否被接受，而且可能在应用真正退出前返回。[Apple 文档](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate%28%29)

Clear 应把可操作目标身份定义为：

- PID；
- 非空 launch date；
- 可用时附加 bundle ID 和 bundle URL；
- 事务预览的观测时间。

launch date 缺失时可以展示应用，但 1.0 不应对它创建退出事务，因为只有 PID 无法抵御 PID 复用。执行前仍要重新取得 `NSRunningApplication` 并复验身份。

### 不能纳入公开接口承诺

当前实现使用 `proc_pid_rusage(..., RUSAGE_INFO_V4, ...)` 读取 `ri_phys_footprint`。虽然 XNU 的资源结构确实包含该字段，[XNU `rusage_info_v4`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/resource.h)，但 Apple 的 `libproc.h` 在文件头明确将其中接口标为 private、未来版本可能变化；同一文件说明 `proc_pid_rusage` 失败时返回 `-1` 并设置 `errno`。[Apple OSS `libproc.h`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/libsyscall/wrappers/libproc/libproc.h)

这意味着 `proc_pid_rusage` 不满足 Clear 已确定的“不使用私有 API”约束。Clear 1.0 不应：

- 把它包装成可靠的公开能力；
- 将失败误写成“该应用占用为 0”；
- 按该值生成高占用应用排行或诊断建议。

若未来要接受 `libproc` 的兼容性风险，必须另立 ADR 和发布门槛；不能在本票中静默改变现有约束。

## 3. 应用族归属

公开的 `NSRunningApplication` 模型提供应用自身的 bundle ID、bundle URL、PID 和 launch date，但没有“拥有这些 helper/XPC/WebContent 进程”的关系字段。[Apple `NSRunningApplication`](https://developer.apple.com/documentation/appkit/nsrunningapplication) XNU 的 `proc_bsdinfo` 虽提供 PPID 和启动时间，[XNU `proc_info.h`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/proc_info.h)，但 `libproc.h` 将访问这些信息的接口整体标为 private，而且父进程关系本身也不是 Apple 文档化的应用所有权契约。

由此可推断，以下启发式都不足以支撑“应用族总内存”：

- bundle ID 字符串前缀：Apple 只承诺它是当前应用的可选标识，没有承诺前缀表示所有权；
- PPID 树：只描述采样时的进程父子关系，不是持久应用归属；
- 可执行文件位于某个 `.app` 内：bundle URL 和进程路径都可能缺失，也没有覆盖被系统服务托管的工作；
- 只取 activation policy 为 regular 的进程：这有意只覆盖普通 GUI 应用，会漏掉 accessory、agent、XPC 和其他辅助进程。

Clear 1.0 的应用归属上限应是“一个由 `NSWorkspace` 发现的普通 GUI 应用主进程”。界面必须明确为“应用主进程”，不得使用“应用总占用”或“应用族”。在严格公开接口模式下，因为连该主进程的 footprint 也没有可接受来源，1.0 只展示运行状态和正常退出入口，不展示内存数值。

## 4. 数据完整性与失败语义

现有 `complete / partial / unavailable` 可以继续作为页面摘要，但不能作为唯一状态。每个信号必须保留：

```swift
struct Observation<Value: Sendable>: Sendable {
    let value: Value?
    let observedAt: Date?
    let status: ObservationStatus
}

enum ObservationStatus: Sendable {
    case available
    case notYetObserved
    case unsupported
    case permissionDenied
    case targetExited
    case targetIdentityChanged
    case transientFailure(source: Source, code: Int32?)
    case malformedResult
    case arithmeticOverflow
}
```

模块级“数据完整性”由这些来源状态投影为覆盖范围、新鲜度和受阻原因，而不是用失败数量计算置信分：

| 情况 | 保留的数据 | 模块表达 |
|---|---|---|
| VM 成功、swap 失败 | VM 样本及时间；swap 失败类别 | `partial`，明确“交换空间暂不可用” |
| 页大小失败 | 仍保留原始页计数供诊断日志使用，但不生成字节值 | `partial`，页面型字节指标不可用 |
| VM 结果字段数量不足 | 不读取未确认字段 | `malformedResult`，拒绝从该结果派生指标 |
| 字节换算溢出 | 其他字段不受影响 | 仅该字段 `arithmeticOverflow` |
| 尚未收到压力变化事件 | 系统 VM 样本仍可用 | 压力事件 `notYetObserved`，不能写成 normal |
| 应用在采样中退出 | 其他应用继续返回 | 该应用 `targetExited`，不是模块失败 |
| PID 仍在但 launch date 改变 | 不沿用旧快照，也不执行退出 | `targetIdentityChanged` |
| AppKit 发现应用但身份字段不足 | 可以展示名称和运行状态 | 完整性注明身份不完整，禁用安全处理 |

摘要规则：

- `complete`：本次产品判断所需的全部必需来源均 available 且未过期；
- `partial`：至少一个必需来源 available，但有来源缺失、过期或受阻；
- `unavailable`：没有足以支持任何当前判断的来源；
- 数据缺失永远不投影为“正常”，也不提高或降低关注级别。

## 5. Swift 6 并发边界

Swift 的 actor 隔离可保护可变状态，`MainActor` 的执行器等价于主 dispatch queue。[Swift 并发文档](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)；[Apple `MainActor`](https://developer.apple.com/documentation/swift/mainactor)

Clear 1.0 应采用以下边界：

- `NSWorkspace`、`NSRunningApplication` 的枚举、缓存和退出请求留在 `@MainActor`；
- 跨隔离域只返回由值类型构成的不可变 `Sendable` 快照，不传递 `NSRunningApplication`；
- 系统 VM 采样由单独 actor 串行化，C 结构和 Mach port 只在一次调用的局部作用域内存在；
- 压力 dispatch source 的 handler 只把值和时间投递给 actor，不直接修改 SwiftUI 状态；
- 取消一次界面刷新不能把已经成功的独立来源抹掉，也不能把旧样本标成新样本。

现有 `SystemMemorySampler` actor、`@MainActor RunningApplicationService` 和 `Sendable` 快照方向正确；需要补的是逐来源状态，而不是再增加 `@unchecked Sendable`。

## 6. Intel 与 Apple Silicon 等价性

Apple 明确指出 Intel Mac 与 Apple Silicon Mac 的原生页大小不同，并要求运行时读取页大小；Rosetta 下的 x86_64 进程又使用 4 KiB 页。[WWDC20：Port your Mac app to Apple silicon](https://developer.apple.com/videos/play/wwdc2020/10214/)

因此架构兼容契约为：

- `host_page_size` 的结果是唯一换算依据；
- 不用编译期 `PAGE_SIZE` 假定，不把 Rosetta 测试当成原生 arm64 测试；
- `vm_statistics64` 的 count、`xsw_usage` 的返回长度和所有乘法在两种架构上都验证；
- Universal Binary 分别在原生 x86_64 与原生 arm64 运行系统采样、故障降级和长时间计数测试；
- 同一原始页计数在不同页大小下得到不同字节数是正确行为，不应通过架构特判“校正”。

XNU 的 `vm_statistics64` 结构说明它在 arm、i386 和 x86_64 上将相关字段统一为 64 位并要求 64 位对齐，[XNU 定义](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/vm_statistics.h)，但这不替代两种原生机器上的运行验收。

## Clear 1.0 具体建议

1. **保留并收紧系统采样器**：继续使用 `ProcessInfo.physicalMemory`、`host_page_size`、`host_statistics64(HOST_VM_INFO64)` 和只读 `vm.swapusage`；为每个来源保存独立状态和时间。
2. **增加压力事件观察器**：用 `DispatchSourceMemoryPressure` 保存最近一次系统事件；首次事件前为未知。Clear 估算必须单独命名和版本化。
3. **修复当前数学语义**：禁止 `free + speculative`；把 `compressor_page_count` 显示为压缩器物理占用；lifetime 计数只显示有效样本差值。
4. **移除 1.0 的 per-process footprint 承诺**：停止用 `proc_pid_rusage` 生成排行、数值和诊断发现，因为 Apple 自己把 `libproc` 接口标为 private。
5. **不实现应用族聚合**：普通 GUI 应用只作为可复验的正常退出目标；没有 launch date 的目标不进入安全事务。
6. **把局部失败做成数据**：字段级 `ObservationStatus` 投影为模块数据完整性；任何缺口都不得被解释为健康。
7. **双架构发布验收**：arm64 与 x86_64 原生机器各自验证运行时页大小、返回结构长度、溢出、来源失败和退出目标复验。

这会缩小“高占用应用排行”的现有功能范围，但它是满足“公开接口、可解释、Intel 兼容、不使用私有 API”四项约束的唯一保守边界。后续诊断阈值和建议动作应建立在这个边界上，而不是先假设完整的应用内存归属存在。
