import ClearMac
import SwiftUI

struct MemoryCenterView: View {
    @ObservedObject var viewModel: MemoryCenterViewModel
    @State private var applicationToQuit: RunningApplicationSnapshot?

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot {
                snapshotContent(snapshot)
            } else if viewModel.isLoading {
                LoadingStateView(
                    title: "正在读取内存状态",
                    message: "只采集系统公开的汇总指标，不读取文件内容。"
                )
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    title: "无法读取内存状态",
                    message: errorMessage,
                    systemImage: "memorychip",
                    actionTitle: "重试"
                ) {
                    Task { await viewModel.refresh() }
                }
            } else {
                EmptyStateView(
                    title: "尚未采样",
                    message: "刷新后可查看估算压力、物理内存、已用内存、压缩器占用和交换空间。",
                    systemImage: "memorychip",
                    actionTitle: "开始采样"
                ) {
                    Task { await viewModel.refresh() }
                }
            }
        }
        .navigationTitle("内存中心")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label(
                        viewModel.isLoading ? "正在刷新" : "刷新",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(viewModel.isLoading)
                .accessibilityHint("重新读取当前系统内存指标")
            }
        }
        .task {
            if viewModel.snapshot == nil {
                await viewModel.refresh()
            }
        }
        .confirmationDialog(
            "请求应用正常退出？",
            isPresented: Binding(
                get: { applicationToQuit != nil },
                set: {
                    if !$0 {
                        applicationToQuit = nil
                    }
                }
            ),
            presenting: applicationToQuit
        ) { application in
            Button("退出“\(application.name)”", role: .destructive) {
                applicationToQuit = nil
                Task {
                    await viewModel.requestQuit(application)
                }
            }
            Button("取消", role: .cancel) {
                applicationToQuit = nil
            }
        } message: { application in
            Text("应用可能有未保存内容。Clear 只会发送正常退出请求，不会自动强制结束。")
        }
    }

    private func snapshotContent(
        _ snapshot: MemorySnapshotViewData
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage = viewModel.errorMessage {
                    InlineMessageView(
                        message: "刷新失败，当前显示上一次结果：\(errorMessage)",
                        style: .warning
                    )
                }

                pressureCard(snapshot)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    MemoryMetricCard(
                        title: "物理内存",
                        value: snapshot.physicalMemoryBytes
                            .clearFormattedBytes,
                        detail: "此 Mac 安装的内存总量",
                        systemImage: "memorychip"
                    )
                    MemoryMetricCard(
                        title: "已用内存（估算）",
                        value: snapshot.estimatedUsedBytes
                            .clearFormattedBytes,
                        detail: "扣除可回收页面后的估算值",
                        systemImage: "chart.pie.fill"
                    )
                    MemoryMetricCard(
                        title: "压缩器占用",
                        value: snapshot.compressedBytes.clearFormattedBytes,
                        detail: "压缩器保存压缩数据使用的物理内存",
                        systemImage: "arrow.down.right.and.arrow.up.left"
                    )
                    MemoryMetricCard(
                        title: "交换空间",
                        value: snapshot.swapUsedBytes?
                            .clearFormattedBytes ?? "不可用",
                        detail: "当前启动周期内使用的磁盘交换空间",
                        systemImage: "internaldrive"
                    )
                }

                InlineMessageView(
                    message: "macOS 会主动使用空闲内存作为缓存。空闲内存更多不一定更快，本工具不会执行伪“释放内存”操作。",
                    style: .information
                )

                if let actionMessage = viewModel.actionMessage {
                    InlineMessageView(
                        message: actionMessage,
                        style: .information
                    )
                }

                applicationSection

                HStack {
                    Label(
                        snapshot.quality.description,
                        systemImage: snapshot.quality == .complete
                            ? "checkmark.seal"
                            : "exclamationmark.circle"
                    )
                    Spacer()
                    Text(
                        snapshot.timestamp.formatted(
                            date: .abbreviated,
                            time: .standard
                        )
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    @ViewBuilder
    private var applicationSection: some View {
        if !viewModel.applications.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("运行中的应用")
                        .font(.headline)
                    Spacer()
                    Text("Clear 不读取其他进程的内存占用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(viewModel.applications.prefix(8))) {
                    application in
                    HStack(spacing: 12) {
                        Image(systemName: "app.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(application.name)
                                .font(.callout.weight(.medium))
                            HStack(spacing: 8) {
                                if application.isActive {
                                    Text("正在使用")
                                } else if application.isHidden {
                                    Text("已隐藏")
                                } else {
                                    Text("正在运行")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("退出") {
                            applicationToQuit = application
                        }
                        .disabled(application.isProtected)
                        .accessibilityHint(
                            application.isProtected
                                ? "系统或身份不明应用受保护"
                                : "确认后发送正常退出请求"
                        )
                    }
                    .padding(12)
                    .background(
                        Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private func pressureCard(
        _ snapshot: MemorySnapshotViewData
    ) -> some View {
        HStack(spacing: 20) {
            Image(systemName: snapshot.pressure.symbolName)
                .font(.system(size: 42))
                .foregroundStyle(snapshot.pressure.displayColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("估算内存压力")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(snapshot.pressure.title)
                    .font(.title.bold())
                Text("这不是 Activity Monitor 私有公式的精确复刻。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            Gauge(value: snapshot.estimatedUsedFraction) {
                Text("估算使用比例")
            } currentValueLabel: {
                Text(
                    snapshot.estimatedUsedFraction,
                    format: .percent.precision(.fractionLength(0))
                )
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(snapshot.pressure.displayColor)
            .frame(width: 86)
            .accessibilityLabel("估算使用比例")
        }
        .padding(20)
        .background(
            snapshot.pressure.displayColor.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct MemoryMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)。\(detail)")
    }
}

private extension MemoryPressureState {
    var displayColor: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }
}
