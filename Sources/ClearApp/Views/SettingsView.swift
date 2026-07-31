import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @State private var showsResetConfirmation = false

    private let ageOptions = [1, 7, 14, 30, 60, 90]

    var body: some View {
        Form {
            Section("扫描范围") {
                Toggle(
                    "用户缓存",
                    isOn: $settingsStore.includesUserCaches
                )
                .accessibilityHint("扫描内置规则明确支持的第三方应用缓存")

                if settingsStore.includesUserCaches {
                    Picker(
                        "缓存最短未修改时间",
                        selection: $settingsStore.cacheMinimumAgeDays
                    ) {
                        ForEach(ageOptions, id: \.self) { days in
                            Text("\(days) 天").tag(days)
                        }
                    }
                }

                Toggle(
                    "旧日志",
                    isOn: $settingsStore.includesOldLogs
                )
                .accessibilityHint("扫描用户资料库中的旧日志")

                if settingsStore.includesOldLogs {
                    Picker(
                        "日志最短未修改时间",
                        selection: $settingsStore.logMinimumAgeDays
                    ) {
                        ForEach(ageOptions, id: \.self) { days in
                            Text("\(days) 天").tag(days)
                        }
                    }
                }

                if !settingsStore.includesUserCaches
                    && !settingsStore.includesOldLogs {
                    InlineMessageView(
                        message: "至少启用一个类别后才能扫描。",
                        style: .warning
                    )
                }

                Text("首版不会泛扫整个缓存目录，也不会扫描系统目录、其他用户、浏览器资料、邮件、照片、容器数据或云端占位文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("隐私与诊断") {
                Text("Clear 的分析、诊断和处理历史只保存在本机，不会上传遥测或使用数据。主动检查更新时才会连接 GitHub。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    openPrivacySettings()
                } label: {
                    Label(
                        "打开“隐私与安全性”设置",
                        systemImage: "hand.raised"
                    )
                }
                .accessibilityHint("打开 macOS 系统设置")
            }

            Section {
                Button("恢复默认设置") {
                    showsResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .frame(maxWidth: 760)
        .confirmationDialog(
            "恢复默认设置？",
            isPresented: $showsResetConfirmation
        ) {
            Button("恢复默认设置", role: .destructive) {
                settingsStore.restoreDefaults()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
