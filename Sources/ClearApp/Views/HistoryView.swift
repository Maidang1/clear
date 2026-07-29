import AppKit
import SwiftUI

struct CleanupHistoryView: View {
    @ObservedObject var historyStore: CleanupHistoryStore
    @State private var showsClearConfirmation = false

    var body: some View {
        Group {
            if historyStore.entries.isEmpty {
                EmptyStateView(
                    title: "暂无清理历史",
                    message: "项目移入废纸篓后，操作摘要会保存在这里。不会记录文件内容。",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                List(historyStore.entries) { entry in
                    historyRow(entry)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("清理历史")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openTrash()
                } label: {
                    Label("打开废纸篓", systemImage: "trash")
                }
                .accessibilityHint("在 Finder 中打开当前用户的废纸篓")

                Button {
                    showsClearConfirmation = true
                } label: {
                    Label("清除历史", systemImage: "clock.badge.xmark")
                }
                .disabled(historyStore.entries.isEmpty)
                .accessibilityHint("只清除本地操作摘要，不删除任何文件")
            }
        }
        .confirmationDialog(
            "清除所有本地清理历史？",
            isPresented: $showsClearConfirmation
        ) {
            Button("清除历史", role: .destructive) {
                historyStore.clear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这不会清空废纸篓，也不会删除其他文件。")
        }
    }

    private func historyRow(
        _ entry: CleanupHistoryEntry
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: entry.status == .completed
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .font(.title2)
            .foregroundStyle(
                entry.status == .completed ? .green : .orange
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.status.title)
                    .font(.headline)
                Text(
                    "\(entry.itemCount) 个项目已移入废纸篓，约 "
                        + entry.estimatedMovedBytes.clearFormattedBytes
                )
                .font(.callout)
                if entry.failedCount > 0 {
                    Text("\(entry.failedCount) 个项目未能处理")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if entry.uncertainCount > 0 {
                    Text("\(entry.uncertainCount) 个项目的最终位置未确认")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Text(
                entry.timestamp.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func openTrash() {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        NSWorkspace.shared.open(trashURL)
    }
}
