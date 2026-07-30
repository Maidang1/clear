import { useState } from "react";

// PROTOTYPE — Selected Health Overview direction from Wayfinder ticket
// "验证统一健康概览的信息架构". Throwaway UI, not production code.

const modules = [
  {
    id: "memory",
    name: "内存",
    state: "内存压力正常，存在 1 个内存占用较高的应用。",
    metricLabel: "最高主进程占用",
    metric: "2.8 GB",
    metricTone: "default",
    findingTitle: "一个应用主进程占用较多内存",
    findingSummary:
      "当前系统内存压力仍然正常。Arc 主进程占用较高，但这不代表必须立即退出。",
    evidence: ["Arc 主进程：2.8 GB", "系统内存压力：正常", "交换空间：1.4 GB"],
    impact:
      "如果应用已不再使用，可以发送正常退出请求；Clear 不会执行伪“释放内存”操作。",
    completeness: "系统指标与应用主进程均已读取。",
    gap: "浏览器辅助进程未聚合为应用族总量",
    action: "查看高占用应用",
  },
  {
    id: "disk",
    name: "磁盘",
    state: "可安全清理的空间已确认。",
    metricLabel: "已确认可回收",
    metric: "12.7 GB",
    metricTone: "blue",
    findingTitle: "可安全清理的空间已确认",
    findingSummary:
      "已检测到多个可安全移除的文件，主要为缓存、日志和本地安装包，不包含系统文件或应用程序本体。",
    evidence: ["缓存文件：8.1 GB", "日志文件：3.2 GB", "本地安装包：1.4 GB"],
    impact:
      "释放磁盘空间，不影响系统或应用功能。处理后不会改变设置或已保存的数据。",
    completeness: "已完成对系统卷与用户目录的扫描。",
    gap: "无法访问 1 个受限目录",
    action: "查看可回收文件",
  },
  {
    id: "startup",
    name: "启动项",
    state: "有 3 个启动项需要你确认是否保留。",
    metricLabel: "需确认的启动项",
    metric: "3 个",
    metricTone: "purple",
    findingTitle: "3 个登录项需要用户判断",
    findingSummary:
      "Clear 可以说明来源和近期使用情况，但无法替你判断这些应用是否仍然重要。",
    evidence: [
      "Docker Desktop：过去 30 天启动 2 次",
      "Dropbox：过去 30 天未打开",
      "Raycast：正在使用，不建议更改",
    ],
    impact:
      "只会禁用你明确选择的项目；不会删除应用，也不会在后台自动修改登录项。",
    completeness: "已枚举系统设置可见的登录项。",
    gap: "部分第三方自启动机制需在模块内进一步核对",
    action: "检查启动项",
  },
  {
    id: "uninstall",
    name: "应用卸载",
    state: "可安全卸载以回收空间，但存在 1 个权限缺口。",
    metricLabel: "已确认可回收",
    metric: "820 MB",
    metricTone: "orange",
    findingTitle: "2 个已移除应用可能留有数据",
    findingSummary:
      "Clear 只会建议处理归属明确的缓存和支持文件；共享目录和归属未知内容默认保留。",
    evidence: [
      "已确认归属的缓存：620 MB",
      "已确认归属的日志：200 MB",
      "共享支持目录：默认保留",
    ],
    impact:
      "候选项目会逐项预览并移入废纸篓；归属不明确的项目不会被预选。",
    completeness: "已完成低权限范围内的应用关联扫描。",
    gap: "1 个应用容器需要用户授权后重新检查",
    action: "查看卸载残留",
  },
];

function Sidebar() {
  const items = ["健康概览", "内存", "磁盘", "启动项", "应用卸载"];
  const secondaryItems = ["历史记录", "设置"];

  return (
    <aside className="sidebar">
      <div className="window-brand">
        <strong>Clear</strong>
        <span>版本 1.4.0（原型）</span>
      </div>

      <nav aria-label="Clear 主导航">
        {items.map((item) => (
          <button
            className={item === "健康概览" ? "nav-item active" : "nav-item"}
            key={item}
            type="button"
          >
            {item}
          </button>
        ))}
      </nav>

      <div className="nav-divider" />

      <nav aria-label="Clear 辅助导航">
        {secondaryItems.map((item) => (
          <button className="nav-item" key={item} type="button">
            {item}
          </button>
        ))}
      </nav>
    </aside>
  );
}

function ModuleCard({ module, selected, onSelect }) {
  return (
    <button
      type="button"
      className={`module-card ${selected ? "selected" : ""}`}
      onClick={() => onSelect(module.id)}
      aria-pressed={selected}
    >
      <span className="module-card-name">{module.name}</span>
      <span className="module-card-state">{module.state}</span>
      <span className="module-card-metric">
        <span>{module.metricLabel}</span>
        <strong className={`metric-${module.metricTone}`}>{module.metric}</strong>
      </span>
    </button>
  );
}

function SafePreviewDialog({ module, onClose }) {
  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <section
        className="preview-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="preview-title"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <p className="dialog-kicker">尚未执行任何处理</p>
        <h2 id="preview-title">{module.name} · 安全处理预览</h2>
        <p>
          下一步只会打开候选范围。你仍需逐项查看、明确确认，Clear
          才会创建安全事务并在执行前重新验证。
        </p>
        <dl>
          <div>
            <dt>当前诊断</dt>
            <dd>{module.findingTitle}</dd>
          </div>
          <div>
            <dt>预期影响</dt>
            <dd>{module.impact}</dd>
          </div>
        </dl>
        <div className="dialog-actions">
          <button className="secondary-button" type="button" onClick={onClose}>
            返回概览
          </button>
          <button className="primary-button" type="button" onClick={onClose}>
            进入候选范围
          </button>
        </div>
      </section>
    </div>
  );
}

export function App() {
  const [selectedId, setSelectedId] = useState("disk");
  const [showPreview, setShowPreview] = useState(false);
  const selected =
    modules.find((module) => module.id === selectedId) ?? modules[1];

  return (
    <div className="app-window">
      <Sidebar />

      <main className="workspace">
        <header className="overview-header">
          <h1>系统当前无紧急风险</h1>
          <p>磁盘空间是当前最值得关注的区域。</p>
        </header>

        <section className="module-grid" aria-label="四模块健康状态">
          {modules.map((module) => (
            <ModuleCard
              key={module.id}
              module={module}
              selected={selected.id === module.id}
              onSelect={setSelectedId}
            />
          ))}
        </section>

        <section className="diagnosis-detail" aria-live="polite">
          <header className="detail-header">
            <h2>
              <span>{selected.name}</span>
              <b>·</b>
              {selected.findingTitle}
              <em>{selected.metric}</em>
            </h2>
            <p>{selected.findingSummary}</p>
          </header>

          <div className="evidence-columns">
            <section>
              <h3>证据（{selected.evidence.length} 项）</h3>
              <ul>
                {selected.evidence.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </section>

            <section>
              <h3>预期影响</h3>
              <p>{selected.impact}</p>
            </section>

            <section>
              <h3>数据完整性</h3>
              <p>{selected.completeness}</p>
              <p className="permission-gap">{selected.gap}</p>
              <button className="text-button" type="button">
                查看详情
              </button>
            </section>
          </div>

          <footer className="next-step">
            <div>
              <h3>下一步建议</h3>
              <p>
                先查看具体候选内容及影响，再决定是否进入安全处理。此页面不会直接执行操作。
              </p>
            </div>
            <button
              className="primary-button"
              type="button"
              onClick={() => setShowPreview(true)}
            >
              {selected.action}
            </button>
          </footer>
        </section>
      </main>

      {showPreview && (
        <SafePreviewDialog
          module={selected}
          onClose={() => setShowPreview(false)}
        />
      )}
    </div>
  );
}
