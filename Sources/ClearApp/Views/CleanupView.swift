import SwiftUI

struct CleanupView: View {
    @ObservedObject var viewModel: CleanupViewModel
    @ObservedObject var settingsStore: AppSettingsStore
    @State private var showsCleanupConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("安全清理")
        .confirmationDialog(
            "将所选项目移入废纸篓？",
            isPresented: $showsCleanupConfirmation
        ) {
            Button("移入废纸篓", role: .destructive) {
                Task { await viewModel.cleanSelectedItems() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "共 \(viewModel.selectedCandidates.count) 个项目，约 "
                    + viewModel.selectedBytes.clearFormattedBytes
                    + "。清空废纸篓前仍可由 Finder 恢复。"
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("只扫描内置白名单缓存和旧日志")
                    .font(.headline)
                Text("扫描本身不会修改文件；清理默认只移入废纸篓。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastScannedAt = viewModel.lastScannedAt {
                Text(
                    "上次扫描 "
                        + lastScannedAt.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await viewModel.scan(options: settingsStore.scanOptions)
                }
            } label: {
                Label(
                    viewModel.isScanning ? "正在扫描" : "扫描",
                    systemImage: "magnifyingglass"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning || viewModel.isCleaning)
                    .accessibilityHint("只读扫描设置中启用的白名单目录")
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isScanning {
            LoadingStateView(
                title: "正在安全扫描",
                message: "仅检查文件元数据，不读取文件内容。大型缓存目录可能需要一些时间。"
            )
        } else if !viewModel.hasCompletedFirstScan {
            EmptyStateView(
                title: "准备扫描",
                message: "扫描结果默认不会选中。确认项目后，才可将其移入废纸篓。",
                systemImage: "shield.checkered",
                actionTitle: "开始扫描"
            ) {
                Task {
                    await viewModel.scan(options: settingsStore.scanOptions)
                }
            }
        } else if let errorMessage = viewModel.errorMessage,
                  viewModel.candidates.isEmpty {
            errorState(message: errorMessage)
        } else {
            resultsContent
        }
    }

    private var resultsContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let noticeMessage = viewModel.noticeMessage {
                        InlineMessageView(
                            message: noticeMessage,
                            style: .success
                        )
                    }

                    if let errorMessage = viewModel.errorMessage {
                        InlineMessageView(
                            message: errorMessage,
                            style: .error
                        )
                    }

                    permissionIssues
                    failureIssues

                    if viewModel.candidates.isEmpty {
                        EmptyStateView(
                            title: "没有可清理项目",
                            message: "当前规则没有发现符合条件的缓存或旧日志。你可以稍后重新扫描。",
                            systemImage: "checkmark.circle"
                        )
                        .frame(minHeight: 330)
                    } else {
                        candidateList
                    }
                }
                .padding(20)
            }

            if !viewModel.candidates.isEmpty {
                Divider()
                actionBar
            }
        }
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("扫描结果")
                    .font(.headline)
                Text("\(viewModel.candidates.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(
                    viewModel.allCandidatesAreSelected
                        ? "取消全选"
                        : "全选"
                ) {
                    viewModel.toggleSelectAll()
                }
                .buttonStyle(.link)
                .accessibilityHint("更改当前所有扫描结果的选择状态")
            }

            LazyVStack(spacing: 8) {
                ForEach(viewModel.candidates) { candidate in
                    CleanupCandidateRow(
                        candidate: candidate,
                        isSelected: Binding(
                            get: {
                                viewModel.selectedCandidateIDs.contains(
                                    candidate.id
                                )
                            },
                            set: {
                                viewModel.setCandidate(
                                    candidate,
                                    selected: $0
                                )
                            }
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var permissionIssues: some View {
        if !viewModel.permissionIssues.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.permissionIssues) { issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.scope)
                                .font(.callout.weight(.medium))
                            Text(issue.message)
                                .font(.caption)
                            Text(issue.recoverySuggestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(
                    "\(viewModel.permissionIssues.count) 个位置未能扫描",
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
                .foregroundStyle(.orange)
            }
            .padding(12)
            .background(
                Color.orange.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }

    @ViewBuilder
    private var failureIssues: some View {
        if !viewModel.failures.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.failures) { failure in
                        Text("\(failure.displayName)：\(failure.message)")
                            .font(.caption)
                            .accessibilityLabel(
                                "\(failure.displayName)，\(failure.message)"
                            )
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(
                    "\(viewModel.failures.count) 个项目未能移动",
                    systemImage: "exclamationmark.octagon"
                )
                .foregroundStyle(.red)
            }
            .padding(12)
            .background(
                Color.red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }

    private var actionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选择 \(viewModel.selectedCandidates.count) 项")
                    .font(.headline)
                Text(
                    viewModel.selectedBytes == 0
                        ? "请选择要处理的项目"
                        : "预计约 "
                            + viewModel.selectedBytes.clearFormattedBytes
                            + "；移入废纸篓不会立即释放空间"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isCleaning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在移动项目")
            }

            Button {
                showsCleanupConfirmation = true
            } label: {
                Label("移入废纸篓", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canClean)
            .accessibilityHint("确认后把所选项目移动到废纸篓")
        }
        .padding(16)
        .background(.bar)
    }

    private func errorState(message: String) -> some View {
        EmptyStateView(
            title: "扫描未完成",
            message: message,
            systemImage: "exclamationmark.triangle",
            actionTitle: "重试"
        ) {
            Task {
                await viewModel.scan(options: settingsStore.scanOptions)
            }
        }
    }
}

private struct CleanupCandidateRow: View {
    let candidate: CleanupCandidate
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("选择 \(candidate.displayName)")

            Image(systemName: candidate.category.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(candidate.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(candidate.category.title)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                    Text(candidate.risk.title)
                        .font(.caption2)
                        .foregroundStyle(
                            candidate.risk == .low ? .green : .orange
                        )
                }

                Text(displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(candidate.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(candidate.estimatedAllocatedBytes.clearFormattedBytes)
                    .font(.callout.monospacedDigit())
                if let modifiedAt = candidate.modifiedAt {
                    Text(
                        modifiedAt.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.08)
                : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isSelected.toggle()
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }

    private var displayPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return candidate.url.path.replacingOccurrences(
            of: homePath,
            with: "~"
        )
    }
}
