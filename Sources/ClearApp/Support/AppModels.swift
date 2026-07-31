import Foundation
import ClearCore

enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case memory
    case cleanup
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .memory: "内存中心"
        case .cleanup: "安全清理"
        case .history: "清理历史"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .memory: "memorychip"
        case .cleanup: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

enum MemoryPressureState: String, Sendable, Equatable {
    case normal
    case warning
    case critical
    case unknown

    var title: String {
        switch self {
        case .normal: "正常"
        case .warning: "需要关注"
        case .critical: "压力较高"
        case .unknown: "暂不可用"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

enum MemorySamplingQuality: Sendable, Equatable {
    case complete
    case partial
    case unavailable

    var description: String {
        switch self {
        case .complete: "完整采样"
        case .partial: "部分指标不可用"
        case .unavailable: "采样不可用"
        }
    }
}

struct MemorySnapshotViewData: Sendable, Equatable {
    let timestamp: Date
    let physicalMemoryBytes: UInt64
    let estimatedUsedBytes: UInt64
    let compressedBytes: UInt64
    let swapUsedBytes: UInt64?
    let pressure: MemoryPressureState
    let quality: MemorySamplingQuality

    var estimatedUsedFraction: Double {
        guard physicalMemoryBytes > 0 else { return 0 }
        return min(1, Double(estimatedUsedBytes) / Double(physicalMemoryBytes))
    }
}

enum CleanupCategory: String, Sendable, Codable, CaseIterable {
    case userCache
    case oldLog

    var title: String {
        switch self {
        case .userCache: "用户缓存"
        case .oldLog: "旧日志"
        }
    }

    var systemImage: String {
        switch self {
        case .userCache: "shippingbox"
        case .oldLog: "doc.text"
        }
    }
}

enum CleanupRisk: String, Sendable, Codable {
    case low
    case attention

    var title: String {
        switch self {
        case .low: "低风险"
        case .attention: "请确认"
        }
    }
}

struct CleanupCandidate: Identifiable, Sendable, Hashable {
    let source: ClearCore.CleanCandidate
    let url: URL
    let displayName: String
    let category: CleanupCategory
    let risk: CleanupRisk
    let estimatedAllocatedBytes: UInt64
    let modifiedAt: Date?
    let reason: String

    var id: UUID { source.id }

    init(source: ClearCore.CleanCandidate) {
        self.source = source
        url = source.url
        displayName = source.displayName
        category = source.category == .oldLog ? .oldLog : .userCache
        risk = source.risk == .low ? .low : .attention
        estimatedAllocatedBytes = source.fingerprint.allocatedSizeBytes
        modifiedAt = source.fingerprint.modifiedAt
        reason = source.requiresApplicationExit
            ? "\(source.explanation) 清理前请退出对应应用。"
            : source.explanation
    }
}

struct PermissionIssue: Identifiable, Sendable, Hashable {
    let id: String
    let scope: String
    let message: String
    let recoverySuggestion: String
}

struct CleanupScanOptions: Sendable, Equatable {
    let includesUserCaches: Bool
    let includesOldLogs: Bool
    let cacheMinimumAgeDays: Int
    let logMinimumAgeDays: Int
}

struct CleanupScanResult: Sendable, Equatable {
    let scannedAt: Date
    let candidates: [CleanupCandidate]
    let permissionIssues: [PermissionIssue]
}

struct CleanupFailure: Identifiable, Sendable, Equatable {
    let id: UUID
    let candidateID: UUID
    let displayName: String
    let message: String

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        displayName: String,
        message: String
    ) {
        self.id = id
        self.candidateID = candidateID
        self.displayName = displayName
        self.message = message
    }
}

struct TrashedCleanupItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let candidateID: UUID
    let displayName: String
    let originalURL: URL
    let trashURL: URL?
    let estimatedAllocatedBytes: UInt64

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        displayName: String,
        originalURL: URL,
        trashURL: URL?,
        estimatedAllocatedBytes: UInt64
    ) {
        self.id = id
        self.candidateID = candidateID
        self.displayName = displayName
        self.originalURL = originalURL
        self.trashURL = trashURL
        self.estimatedAllocatedBytes = estimatedAllocatedBytes
    }
}

struct UncertainCleanupMutation: Identifiable, Sendable, Equatable {
    let id: UUID
    let candidateID: UUID
    let displayName: String
    let originalURL: URL
    let lastKnownTrashURL: URL?
    let estimatedAllocatedBytes: UInt64

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        displayName: String,
        originalURL: URL,
        lastKnownTrashURL: URL?,
        estimatedAllocatedBytes: UInt64
    ) {
        self.id = id
        self.candidateID = candidateID
        self.displayName = displayName
        self.originalURL = originalURL
        self.lastKnownTrashURL = lastKnownTrashURL
        self.estimatedAllocatedBytes = estimatedAllocatedBytes
    }
}

struct CleanupExecutionResult: Sendable, Equatable {
    let finishedAt: Date
    let trashedItems: [TrashedCleanupItem]
    let uncertainMutations: [UncertainCleanupMutation]
    let failures: [CleanupFailure]

    var estimatedMovedBytes: UInt64 {
        trashedItems.reduce(0) { partialResult, item in
            partialResult + item.estimatedAllocatedBytes
        }
    }
}

enum CleanupHistoryStatus: String, Codable, Sendable {
    case completed
    case partiallyCompleted

    var title: String {
        switch self {
        case .completed: "已完成"
        case .partiallyCompleted: "部分完成"
        }
    }
}

struct CleanupHistoryEntry: Identifiable, Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case itemCount
        case uncertainCount
        case estimatedMovedBytes
        case failedCount
        case status
    }

    let id: UUID
    let timestamp: Date
    let itemCount: Int
    let uncertainCount: Int
    let estimatedMovedBytes: UInt64
    let failedCount: Int
    let status: CleanupHistoryStatus

    init(
        id: UUID = UUID(),
        timestamp: Date,
        itemCount: Int,
        uncertainCount: Int,
        estimatedMovedBytes: UInt64,
        failedCount: Int,
        status: CleanupHistoryStatus
    ) {
        self.id = id
        self.timestamp = timestamp
        self.itemCount = itemCount
        self.uncertainCount = uncertainCount
        self.estimatedMovedBytes = estimatedMovedBytes
        self.failedCount = failedCount
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        uncertainCount = try container.decodeIfPresent(
            Int.self,
            forKey: .uncertainCount
        ) ?? 0
        estimatedMovedBytes = try container.decode(
            UInt64.self,
            forKey: .estimatedMovedBytes
        )
        failedCount = try container.decode(
            Int.self,
            forKey: .failedCount
        )
        status = try container.decode(
            CleanupHistoryStatus.self,
            forKey: .status
        )
    }
}

extension UInt64 {
    var clearFormattedBytes: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: self),
            countStyle: .memory
        )
    }
}
