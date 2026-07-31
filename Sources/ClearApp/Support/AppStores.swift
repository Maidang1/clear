import Combine
import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    private enum Key {
        static let includesUserCaches = "clear.scan.includesUserCaches"
        static let includesOldLogs = "clear.scan.includesOldLogs"
        static let cacheMinimumAgeDays = "clear.scan.cacheMinimumAgeDays"
        static let logMinimumAgeDays = "clear.scan.logMinimumAgeDays"
        static let legacySharesAnonymousDiagnostics =
            "clear.privacy.sharesAnonymousDiagnostics"
    }

    private let defaults: UserDefaults

    @Published var includesUserCaches: Bool {
        didSet { defaults.set(includesUserCaches, forKey: Key.includesUserCaches) }
    }

    @Published var includesOldLogs: Bool {
        didSet { defaults.set(includesOldLogs, forKey: Key.includesOldLogs) }
    }

    @Published var cacheMinimumAgeDays: Int {
        didSet {
            defaults.set(cacheMinimumAgeDays, forKey: Key.cacheMinimumAgeDays)
        }
    }

    @Published var logMinimumAgeDays: Int {
        didSet {
            defaults.set(logMinimumAgeDays, forKey: Key.logMinimumAgeDays)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(
            forKey: Key.legacySharesAnonymousDiagnostics
        )

        includesUserCaches = defaults.object(
            forKey: Key.includesUserCaches
        ) as? Bool ?? true
        includesOldLogs = defaults.object(
            forKey: Key.includesOldLogs
        ) as? Bool ?? true

        let storedCacheAge = defaults.integer(
            forKey: Key.cacheMinimumAgeDays
        )
        cacheMinimumAgeDays = storedCacheAge == 0 ? 7 : storedCacheAge

        let storedLogAge = defaults.integer(
            forKey: Key.logMinimumAgeDays
        )
        logMinimumAgeDays = storedLogAge == 0 ? 30 : storedLogAge

    }

    var scanOptions: CleanupScanOptions {
        CleanupScanOptions(
            includesUserCaches: includesUserCaches,
            includesOldLogs: includesOldLogs,
            cacheMinimumAgeDays: cacheMinimumAgeDays,
            logMinimumAgeDays: logMinimumAgeDays
        )
    }

    func restoreDefaults() {
        includesUserCaches = true
        includesOldLogs = true
        cacheMinimumAgeDays = 7
        logMinimumAgeDays = 30
    }
}

@MainActor
final class CleanupHistoryStore: ObservableObject {
    private static let storageKey = "clear.cleanup.history.v1"
    private static let maximumEntryCount = 50

    private let defaults: UserDefaults
    @Published private(set) var entries: [CleanupHistoryEntry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(
                [CleanupHistoryEntry].self,
                from: data
              ) else {
            entries = []
            return
        }
        entries = decoded.sorted { $0.timestamp > $1.timestamp }
    }

    func record(_ result: CleanupExecutionResult) {
        guard !result.trashedItems.isEmpty
                || !result.uncertainMutations.isEmpty
                || !result.failures.isEmpty
        else {
            return
        }

        let status: CleanupHistoryStatus = result.failures.isEmpty
            ? .completed
            : .partiallyCompleted
        let uncertainCandidateIDs = Set(
            result.uncertainMutations.map(\.candidateID)
        )
        let definiteFailureCount = result.failures.reduce(into: 0) {
            count, failure in
            if !uncertainCandidateIDs.contains(failure.candidateID) {
                count += 1
            }
        }
        let entry = CleanupHistoryEntry(
            timestamp: result.finishedAt,
            itemCount: result.trashedItems.count,
            uncertainCount: result.uncertainMutations.count,
            estimatedMovedBytes: result.estimatedMovedBytes,
            failedCount: definiteFailureCount,
            status: status
        )
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(Self.maximumEntryCount))
        persist()
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
