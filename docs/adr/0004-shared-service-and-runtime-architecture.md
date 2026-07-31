# ADR 0004：共享服务与运行时架构

- 状态：已接受
- 日期：2026-07-31
- 决策来源：[定义共享服务架构、模块边界与后台资源预算](https://github.com/Maidang1/clear/issues/8)

## 背景

Clear 要从内存与磁盘 MVP 扩展到健康概览、启动项和应用卸载，同时保留 Swift Package 的清晰边界、低后台开销和 Intel / Apple Silicon 一致行为。若四个模块各自创建权限、历史、确认和后台生命周期，安全语义会分叉，资源预算也无法统一验证。

## 决策

保留 `ClearCore → ClearMac → ClearApp` 的单向依赖：

- `ClearCore`：无 AppKit 的领域模型、诊断规则、`ModuleDigest`、安全事务状态机、journal 协议、历史 schema 与排序纯函数；
- `ClearMac`：公开 macOS API 的采集器、能力探测、目标身份、复验、执行与独立验证适配器；
- `ClearApp`：单一 composition root、SwiftUI 状态容器、主窗口、菜单栏、权限说明和统一事务界面。

每个模块提供强类型 `Observation`、`Finding` 与 `Recommendation`，只通过 `ModuleDigest` 投影到健康概览。禁止跨模块共享未经解释的 `[String: Any]` 或把 UI 文案当作状态。

主窗口与菜单栏首版同进程，使用 `WindowGroup + MenuBarExtra`。可选“登录时启动 Clear”只管理 Clear 自身的 `SMAppService`；不引入独立 Helper、XPC 服务或 root daemon。菜单栏仅展示最近摘要、触发刷新和打开主窗口，不能自动执行副作用。

后台调度以系统事件和可见性驱动：

- 内存中心可见时按模块规格采样；
- 菜单栏安静状态使用低频公开信号与事件通知；
- 磁盘、启动项和卸载盘点只在用户打开页面、明确刷新或已知根发生变化后运行；
- 睡眠时停止计时器，唤醒后创建新的 observation generation，旧快照只作为 `stale` 显示；
- 所有扫描可取消、有预算，并使用 utility QoS。

权限采用作用域化能力结果，而不是全局“FDA 已开启”布尔值。每次观测记录已覆盖范围、受阻范围和原因；授权变化使相关 observation 与事务预览失效。

内存模块只使用公开系统 VM 计数、系统压力事件、压缩和交换证据。Clear 1.0 不读取私有或容易误导的进程 footprint，不将 GUI 主进程数据冒充为完整应用内存。

## 资源硬门槛

- 菜单栏安静状态：CPU median ≤ 0.2%、p95 ≤ 1%，steady physical footprint ≤ 50 MiB；
- 内存中心可见：CPU median ≤ 2%、p95 ≤ 8%，steady physical footprint ≤ 80 MiB；
- 30 分钟稳定窗口内无持续内存增长；睡眠期间无主动采样，唤醒后 5 秒内恢复状态；
- 所有指标分别使用 Release Universal build 在 Intel 与 Apple Silicon 真机验证。

## 备选方案

### 每个模块持有独立 service locator

拒绝。依赖和权限状态无法审计，事务与历史容易产生多个事实来源。

### 独立常驻 Helper

拒绝。当前功能不需要提权或进程隔离，Helper 会扩大未签名分发、升级、权限与资源风险。

### 高频轮询所有模块

拒绝。磁盘和启动项变化速度不足以支持该成本，也会违反后台资源门槛。

## 影响

- `ClearApp.swift` 成为唯一 composition root，测试通过协议注入假实现。
- 现有磁盘 `CleanupCoordinator` 迁移为安全事务适配器，不再拥有独立确认语义。
- `UserDefaults` 只保留偏好；历史与 journal 使用版本化、有界的 Application Support 存储。
- 所有模块必须显式处理权限拒绝、取消、睡眠/唤醒、观测代次和数据过期。
