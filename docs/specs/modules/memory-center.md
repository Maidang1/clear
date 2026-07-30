# Clear 1.0 内存中心规格

- 状态：决策完成
- 地图：[Clear 1.0 内存中心：决策地图](https://github.com/Maidang1/clear/issues/12)
- 研究：`docs/research/2026-07-31-memory-observation-boundary.md`
- 依赖：ADR 0001、ADR 0002、ADR 0003

## 用户结果

用户能理解当前 Mac 是否出现持续内存压力、哪些公开信号支持判断、数据是否完整，以及可以选择哪些普通 GUI 应用发送正常退出请求。Clear 不承诺“释放 RAM”，不读取其他进程的私有 footprint，也不展示应用族总内存。

## 公开观测边界

保留以下独立来源：

- `ProcessInfo.physicalMemory`；
- 运行时 `host_page_size`；
- `host_statistics64(HOST_VM_INFO64)` 的系统汇总页计数；
- 只读 `vm.swapusage`；
- `DispatchSourceMemoryPressure` 的变化事件；
- `NSWorkspace.runningApplications` 的普通 GUI 应用身份和运行状态。

每个来源分别保存值、时间、状态和失败原因。页大小、返回字段数量和字节换算必须验证。`free_count` 已包含 speculative pages，任何派生值都不得重复相加。`compressor_page_count` 显示为“压缩器占用”。

`proc_pid_rusage` 和其他 `libproc` 接口不进入 1.0，因为 Apple 将该接口族标为 private。应用列表不显示、排序或诊断 per-process footprint；不实现 helper/XPC/WebContent 的应用族聚合。

## 诊断

系统压力事件和内存状态估算独立保存。系统事件首次到达前为 `notYetObserved`。

### 关注级别

- `actNow`：
  - 新鲜的系统 `critical` 事件；或
  - 连续三个有效样本中，可用头部代理低于物理内存 5%，且压缩或 swap-out lifetime 计数持续增长。
- `review`：
  - 新鲜的系统 `warning` 事件；或
  - 连续三个有效样本中，可用头部代理低于 15%，并存在压缩或 swap-out 活动。
- `observe`：
  - 压缩器占用达到物理内存 25% 或 swap used 达到 10%，但没有新鲜的活跃压力证据；或
  - 尚未收到系统压力事件，但完整 VM 样本未显示持续 churn。
- `clear`：新鲜的系统 `normal` 事件，加上连续有效样本没有压缩/swap-out churn。
- `undetermined`：没有足以支持当前判断的新鲜来源。

“可用头部代理”仅由不重复的 VM 队列形成，并在 UI 标为 Clear 估算。历史 swap 或高压缩占用只能产生 `observe`，不能单独产生 `actNow`。

系统事件在前台 90 秒、菜单栏 5 分钟后视为过期；过期后由新样本重新判断，不能无限延续警告。

## 应用列表与正常退出

应用列表只展示普通 GUI 应用的名称、当前/隐藏/运行状态，并明确说明 Clear 不读取其内存占用。当前应用优先，其余按名称稳定排序。

可创建退出事务的目标必须有：

- PID；
- 非空 launch date；
- 可用时的 bundle ID 与 bundle URL；
- 预览观测时间；
- 非 Clear、非受保护系统应用。

流程：

1. 预览说明应用可能有未保存内容，Clear 只发送正常退出请求；
2. 用户确认具体应用；
3. 执行前复验 PID 与 launch date；
4. 调用公开 `terminate()`；
5. 监听退出通知并在 10 秒超时后重新查询；
6. 原目标消失为成功；请求被拒绝或仍运行为明确失败；身份漂移时不操作新进程。

不提供 force terminate。恢复路径是由用户重新打开应用；Clear 不自动重启。

## 数据完整性

- `complete`：当前判断需要的 VM、页大小、物理内存和相邻计数均新鲜，且系统压力事件状态已知。
- `partial`：至少一个系统来源可用，但 swap、压力事件或部分 VM 字段缺失/过期。
- `stale`：前台样本超过 5 秒，或菜单栏 heartbeat 超过 2 分钟。
- `unavailable`：没有来源足以生成任何当前判断。

应用目标身份不完整只禁用该应用的退出事务，不使系统内存观测整体失败。

## 采样与历史

| 状态 | 系统采样 | 应用清单 |
| --- | --- | --- |
| 内存页可见 | 1 秒 | 首次快照 + NSWorkspace 事件 |
| 其他窗口可见 | 5 秒 | 只消费事件更新 |
| 菜单栏安静 | 压力事件 + 最慢 60 秒 heartbeat | 不轮询 |
| warning/critical | 立即补一个系统样本 | 不做 footprint 扫描 |
| 低电量/高热 | 压力事件 + 最慢 120 秒 heartbeat | 不轮询 |
| 会话不活跃/睡眠 | 停止 | 停止 |
| 唤醒 | 新 observation generation，立即轻量采样 | 延迟 2–5 秒重建 |

1 秒原始样本只保存在 15 分钟有界内存 ring。持久化 1 分钟桶 48 小时、1 小时桶 30 天；睡眠、唤醒、计数回退或采样器重启后禁止跨 generation 计算速率。

## 资源与验收

- 内存页可见：CPU median ≤ 2%、p95 ≤ 8%，steady footprint ≤ 80 MiB。
- 菜单栏安静：CPU median ≤ 0.2%、p95 ≤ 1%，steady footprint ≤ 50 MiB。
- 测试覆盖来源独立失败、字段长度、算术溢出、speculative 不重复、lifetime delta、事件未知/过期、睡眠代次、PID 复用、退出拒绝和超时。
- Intel 与 Apple Silicon 使用运行时页大小，并分别在原生机器完成同级功能、故障和 72 小时稳定性验证。
