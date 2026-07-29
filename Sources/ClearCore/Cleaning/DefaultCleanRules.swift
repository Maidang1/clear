import Foundation

public enum DefaultCleanRules {
    private static let day: TimeInterval = 86_400

    /// Returns Clear's built-in v1 allowlist.
    ///
    /// Every rule names one exact directory. The broad `~/Library/Caches` and
    /// `~/Library/Logs` roots are intentionally never returned as rules.
    public static func make() -> [CleanRule] {
        make(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func make(homeDirectory: URL) -> [CleanRule] {
        let library = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
        let caches = library
            .appendingPathComponent("Caches", isDirectory: true)
        let logs = library
            .appendingPathComponent("Logs", isDirectory: true)

        return [
            cacheRule(
                id: "cache.google.chrome",
                name: "Google Chrome 缓存",
                bundleIdentifier: "com.google.Chrome",
                root: caches.appendingPathComponent(
                    "com.google.Chrome",
                    isDirectory: true
                )
            ),
            cacheRule(
                id: "cache.microsoft.vscode",
                name: "Visual Studio Code 缓存",
                bundleIdentifier: "com.microsoft.VSCode",
                root: caches.appendingPathComponent(
                    "com.microsoft.VSCode",
                    isDirectory: true
                )
            ),
            cacheRule(
                id: "cache.slack",
                name: "Slack 缓存",
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                root: caches.appendingPathComponent(
                    "com.tinyspeck.slackmacgap",
                    isDirectory: true
                )
            ),
            cacheRule(
                id: "cache.spotify",
                name: "Spotify 缓存",
                bundleIdentifier: "com.spotify.client",
                root: caches.appendingPathComponent(
                    "com.spotify.client",
                    isDirectory: true
                )
            ),
            cacheRule(
                id: "cache.discord",
                name: "Discord 缓存",
                bundleIdentifier: "com.hnc.Discord",
                root: caches.appendingPathComponent(
                    "com.hnc.Discord",
                    isDirectory: true
                )
            ),
            cacheRule(
                id: "cache.zoom",
                name: "Zoom 缓存",
                bundleIdentifier: "us.zoom.xos",
                root: caches.appendingPathComponent(
                    "us.zoom.xos",
                    isDirectory: true
                )
            ),
            CleanRule(
                id: "logs.diagnostic-reports",
                category: .oldLog,
                rootURL: logs.appendingPathComponent(
                    "DiagnosticReports",
                    isDirectory: true
                ),
                displayName: "旧诊断报告",
                explanation: "超过 30 天的崩溃与诊断报告；删除后不会影响应用数据。",
                minimumAge: 30 * day,
                maximumDepth: 2,
                maximumEntryCount: 10_000,
                risk: .low
            )
        ]
    }

    private static func cacheRule(
        id: String,
        name: String,
        bundleIdentifier: String,
        root: URL
    ) -> CleanRule {
        CleanRule(
            id: id,
            category: .applicationCache,
            rootURL: root,
            displayName: name,
            explanation: "超过 7 天未修改的可再生缓存。建议先退出对应应用。",
            minimumAge: 7 * day,
            maximumDepth: 12,
            maximumEntryCount: 50_000,
            risk: .attention,
            relatedBundleIdentifier: bundleIdentifier,
            requiresApplicationExit: true
        )
    }
}
