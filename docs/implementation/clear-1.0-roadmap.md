# Clear 1.0 实施路线

- 主规格：`docs/specs/clear-1.0.md`
- 跟踪票据：[收敛 MVP 迁移、增量发布切片与 Clear 1.0 主规格](https://github.com/Maidang1/clear/issues/24)
- 原则：纵向切片、旧入口随迁移删除、每个切片保持可发布

## 当前基线

已完成的规划与安全修正：

- 四张模块决策地图和主规格已闭合；
- 删除匿名诊断共享设置；
- 删除私有进程 footprint 展示和强退能力；
- speculative pages 不再重复计入可用内存；
- 内存和磁盘已有可复用观测、规则、路径安全和废纸篓基础；
- 健康概览交互原型已验证四模块态势矩阵。

当前执行环境没有 Swift 工具链，因此 Swift 编译与测试必须由 macOS GitHub Actions 和真机继续验证。

## Phase 1：共享领域与本地基础

目标：先建立唯一安全语义，不改变用户可见功能。

- [ ] 在 `ClearCore/Observations` 定义 `ObservationEnvelope`、generation、freshness 和 `DataCompleteness`；
- [ ] 在 `ClearCore/Health` 定义 `AttentionLevel`、`ModuleDigest` 和稳定排序纯函数；
- [ ] 在 `ClearCore/Transactions` 定义不可变 preview、摘要确认、item state、transaction state 与 reducer；
- [ ] 定义 `TransactionJournal`、`TreatmentHistoryStore`、`DiagnosticHistoryStore` 协议和版本化 schema；
- [ ] 在 `ClearMac` 实现 Application Support 原子存储、权限模式和保留上限；
- [ ] 在 `ClearMac/Capabilities` 实现按资源的 capability probe；
- [ ] 将 `ClearApp.swift` 收敛为唯一 composition root；
- [ ] 测试 reducer、重复执行、确认失效、损坏存储、迁移、保留与脱敏。

完成定义：没有模块直接把副作用结果写入 `UserDefaults`；所有新副作用只能经统一事务协调器。

## Phase 2：迁移内存与磁盘

### 内存中心

- [ ] 将 `SystemMemorySampler` 输出包装为带 generation 的 observation；
- [ ] 分离系统压力事件与 Clear 估算，落实模块阈值、迟滞和新鲜度；
- [ ] 运行应用清单只保留可解释身份、活跃状态与普通退出资格；
- [ ] 把正常退出请求实现为事务适配器：复验 PID/启动时间、请求退出、独立验证；
- [ ] 覆盖应用拒绝退出、PID 重用、已退出、受保护应用、取消和睡眠/唤醒。

### 安全磁盘清理

- [ ] 给内置清理规则增加稳定 ID 与版本；
- [ ] 将 scan snapshot 绑定规则版本、文件/卷身份、根和预算；
- [ ] 将 `CleanupCoordinator` 迁入统一事务，加入 journal 与废纸篓身份验证；
- [ ] UI 使用候选分组、完整性和逐项结果，不显示保证释放的字节；
- [ ] 覆盖符号链接、挂载点、硬链接、路径逃逸、身份漂移、部分完成、取消与 reconcile。

完成定义：内存与磁盘都输出 `ModuleDigest`，旧直接执行入口不可达。

## Phase 3：健康概览与菜单栏

- [ ] 将原型的四模块态势矩阵实现为 SwiftUI 首页；
- [ ] 抽取统一 `ModuleDigestView`、证据、完整性、权限和安全下一步组件；
- [ ] 保证后台更新不覆盖用户手动选择；
- [ ] 添加同进程 `MenuBarExtra`，默认关闭，只显示摘要、刷新和打开窗口；
- [ ] 添加可见性与事件驱动调度器，睡眠停止、唤醒换代；
- [ ] 添加本地资源测量方案和诊断导出格式。

完成定义：即使启动项和卸载尚未开放，首页也用“未实现/数据不可用”真实表达，不显示伪健康状态。

## Phase 4：启动项

- [ ] 只读枚举三个 launchd 声明目录，限制单项大小、总量和并发；
- [ ] 实现 plist、目标、触发、所有权与 Mach-O 架构解析；
- [ ] 输出静态声明事实、配置问题与 Open at Login/BTM 数据缺口；
- [ ] 实现 `SMAppService.openSystemSettingsLoginItems()` 交接；
- [ ] 实现 Clear 自有登录启动的 register/unregister 事务，实验开关默认关闭；
- [ ] 通过 ad-hoc Release 在 Intel 与 Apple Silicon 验证后才开放自有开关。

完成定义：不读取 BTM 私有数据库、不修改第三方 plist、不把交接声称为禁用成功。

## Phase 5：应用卸载

- [ ] 盘点两个应用根，可靠解析 package 身份和 fat/thin 架构；
- [ ] 实现精确归属规则与用户承载/共享/歧义排除；
- [ ] 实现单应用预览，Preferences 默认关闭；
- [ ] 正常退出作为独立前置动作，退出后重扫；
- [ ] 为 `.app` package 实现同卷废纸篓 mover、全量预检、逐项 journal 和独立验证；
- [ ] 实现部分完成、`uncertain` 停止扩大、废纸篓定位与手动恢复说明。

完成定义：没有批量卸载、厂商脚本、容器清理或永久删除路径。

## Phase 6：1.0 发布候选

- [ ] 完成设置/历史 schema 迁移和隐私导出审核；
- [ ] 更新 README、安装、权限、恢复、故障排查和安全模型；
- [ ] GitHub Actions 构建 Universal app，执行测试，打包 DMG 并生成 SHA-256；
- [ ] 在 Intel 与 Apple Silicon 分别执行权限矩阵、四模块关键流程和升级验收；
- [ ] 两类机器分别完成 72 小时菜单栏稳定运行；
- [ ] 对照 `docs/specs/clear-1.0.md` 的每条硬门槛签署本地发布清单；
- [ ] 只有全部通过后创建 GitHub `v1.0.0` Release。

## 每个 PR 的完成条件

- 用户可观察结果和降级文案与规格一致；
- 新状态使用强类型模型，平台 API 隔离在 `ClearMac`；
- 副作用经过统一事务，不新增旁路；
- 单元测试覆盖正常、权限拒绝、状态漂移、取消和失败；
- `swift test` 与 Universal build 在 macOS CI 通过；
- 无遥测、自动网络请求、私有 API、root Helper 或新的永久删除路径；
- Intel 与 Apple Silicon 行为差异有明确证据和真机验收项。
