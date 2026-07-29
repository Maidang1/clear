import ClearCore
import ClearMac
import Foundation

protocol MemorySnapshotProviding: Sendable {
    func snapshot() async throws -> MemorySnapshotViewData
}

@MainActor
protocol CleanupServicing: Sendable {
    func scan(options: CleanupScanOptions) async throws -> CleanupScanResult
    func moveToTrash(
        _ candidates: [CleanupCandidate]
    ) async -> CleanupExecutionResult
}

enum AppServiceError: LocalizedError {
    case noScanCategorySelected

    var errorDescription: String? {
        switch self {
        case .noScanCategorySelected:
            "请先在设置中启用至少一种扫描类别。"
        }
    }
}

struct ClearMacMemorySnapshotProvider: MemorySnapshotProviding {
    private let sampler: SystemMemorySampler

    init(sampler: SystemMemorySampler = SystemMemorySampler()) {
        self.sampler = sampler
    }

    func snapshot() async -> MemorySnapshotViewData {
        let sample = await sampler.sample()
        let total = sample.physicalMemoryBytes
        let reclaimable = clampedSum(
            [
                sample.freeMemoryBytes ?? 0,
                sample.inactiveMemoryBytes ?? 0,
                sample.speculativeMemoryBytes ?? 0
            ],
            upperBound: total
        )

        return MemorySnapshotViewData(
            timestamp: sample.timestamp,
            physicalMemoryBytes: total,
            estimatedUsedBytes: total - reclaimable,
            compressedBytes: sample.compressedMemoryBytes ?? 0,
            swapUsedBytes: sample.swapUsedBytes,
            pressure: pressureState(from: sample.estimatedPressureLevel),
            quality: samplingQuality(from: sample.samplingQuality)
        )
    }

    private func clampedSum(
        _ values: [UInt64],
        upperBound: UInt64
    ) -> UInt64 {
        var total: UInt64 = 0
        for value in values {
            let (sum, overflow) = total.addingReportingOverflow(value)
            if overflow || sum >= upperBound {
                return upperBound
            }
            total = sum
        }
        return total
    }

    private func pressureState(
        from level: MemoryPressureLevel
    ) -> MemoryPressureState {
        switch level {
        case .unknown: .unknown
        case .normal: .normal
        case .warning: .warning
        case .critical: .critical
        }
    }

    private func samplingQuality(
        from quality: ClearMac.MemorySamplingQuality
    ) -> MemorySamplingQuality {
        switch quality {
        case .complete: .complete
        case .partial: .partial
        case .unavailable: .unavailable
        }
    }
}

@MainActor
struct LocalCleanupService: CleanupServicing {
    private let scanner: ScanCoordinator
    private let cleanup: CleanupCoordinator
    private let applicationService: RunningApplicationService
    private let homeDirectory: URL

    init(
        scanner: ScanCoordinator = ScanCoordinator(candidateLimit: 300),
        cleanup: CleanupCoordinator = CleanupCoordinator(),
        applicationService: RunningApplicationService =
            RunningApplicationService(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.scanner = scanner
        self.cleanup = cleanup
        self.applicationService = applicationService
        self.homeDirectory = homeDirectory
    }

    func scan(options: CleanupScanOptions) async throws -> CleanupScanResult {
        guard options.includesUserCaches || options.includesOldLogs else {
            throw AppServiceError.noScanCategorySelected
        }

        let cacheAge = TimeInterval(
            max(1, options.cacheMinimumAgeDays) * 86_400
        )
        let logAge = TimeInterval(
            max(1, options.logMinimumAgeDays) * 86_400
        )
        let rules = DefaultCleanRules.make()
            .compactMap { rule -> CleanRule? in
                switch rule.category {
                case .applicationCache:
                    guard options.includesUserCaches else {
                        return nil
                    }
                    return rule.withMinimumAge(cacheAge)
                case .oldLog:
                    guard options.includesOldLogs else {
                        return nil
                    }
                    return rule.withMinimumAge(logAge)
                }
            }

        let result = try await scanner.scan(rules: rules)
        return CleanupScanResult(
            scannedAt: result.scannedAt,
            candidates: result.candidates.map {
                CleanupCandidate(source: $0)
            },
            permissionIssues: result.issues.map {
                permissionIssue($0)
            }
        )
    }

    func moveToTrash(
        _ candidates: [CleanupCandidate]
    ) async -> CleanupExecutionResult {
        let displayNames = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.id, $0.displayName) }
        )
        let plan = await cleanup.makePlan(
            candidates: candidates.map(\.source)
        )
        let applicationService = applicationService
        let result = await cleanup.execute(
            plan,
            isApplicationRunning: { bundleIdentifier in
                await applicationService.isApplicationFamilyRunning(
                    bundleIdentifier: bundleIdentifier
                )
            }
        )

        return CleanupExecutionResult(
            finishedAt: result.finishedAt,
            trashedItems: result.trashedItems.map { item in
                TrashedCleanupItem(
                    candidateID: item.candidateID,
                    displayName: displayNames[item.candidateID] ?? "未知项目",
                    originalURL: item.originalURL,
                    trashURL: item.resultingTrashURL,
                    estimatedAllocatedBytes: item.estimatedAllocatedBytes
                )
            },
            uncertainMutations: result.uncertainMutations.map { item in
                UncertainCleanupMutation(
                    candidateID: item.candidateID,
                    displayName: displayNames[item.candidateID] ?? "未知项目",
                    originalURL: item.originalURL,
                    lastKnownTrashURL: item.lastKnownTrashURL,
                    estimatedAllocatedBytes: item.estimatedAllocatedBytes
                )
            },
            failures: result.failures.map { failure in
                CleanupFailure(
                    candidateID: failure.candidateID,
                    displayName: failure.displayName,
                    message: failure.message
                )
            }
        )
    }

    private func permissionIssue(_ issue: ScanIssue) -> PermissionIssue {
        let recoverySuggestion: String
        switch issue.kind {
        case .permissionDenied:
            recoverySuggestion = "检查“隐私与安全性”中的文件访问权限后重试。"
        case .entryLimitExceeded:
            recoverySuggestion = "为保证安全，Clear 不会扩大本次扫描上限。"
        case .unsafePath, .changedDuringScan, .unreadableMetadata:
            recoverySuggestion = "此项目已跳过；重新扫描后仍异常则无需处理。"
        }

        return PermissionIssue(
            id: issue.id.uuidString,
            scope: abbreviatedPath(issue.path),
            message: issue.message,
            recoverySuggestion: recoverySuggestion
        )
    }

    private func abbreviatedPath(_ path: String) -> String {
        path.replacingOccurrences(
            of: homeDirectory.path,
            with: "~"
        )
    }
}
