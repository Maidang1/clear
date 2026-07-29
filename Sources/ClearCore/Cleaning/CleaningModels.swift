import Foundation

public enum CleanCategory: String, Codable, CaseIterable, Sendable {
    case applicationCache
    case oldLog
}

public enum CleanRisk: String, Codable, Sendable {
    case low
    case attention
}

/// A versioned, exact-root rule. Rules may narrow Clear's scan scope, but they
/// must never accept arbitrary user-provided roots in the normal cleanup flow.
public struct CleanRule: Identifiable, Hashable, Sendable {
    public let id: String
    public let version: Int
    public let category: CleanCategory
    public let rootURL: URL
    public let displayName: String
    public let explanation: String
    public let minimumAge: TimeInterval
    public let maximumDepth: Int
    public let maximumEntryCount: Int
    public let risk: CleanRisk
    public let relatedBundleIdentifier: String?
    public let requiresApplicationExit: Bool

    init(
        id: String,
        version: Int = 1,
        category: CleanCategory,
        rootURL: URL,
        displayName: String,
        explanation: String,
        minimumAge: TimeInterval,
        maximumDepth: Int = 12,
        maximumEntryCount: Int = 50_000,
        risk: CleanRisk,
        relatedBundleIdentifier: String? = nil,
        requiresApplicationExit: Bool = false
    ) {
        self.id = id
        self.version = version
        self.category = category
        self.rootURL = rootURL.standardizedFileURL
        self.displayName = displayName
        self.explanation = explanation
        self.minimumAge = max(0, minimumAge)
        self.maximumDepth = max(1, maximumDepth)
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.risk = risk
        self.relatedBundleIdentifier = relatedBundleIdentifier
        self.requiresApplicationExit = requiresApplicationExit
    }

    public func withMinimumAge(_ minimumAge: TimeInterval) -> CleanRule {
        CleanRule(
            id: id,
            version: version,
            category: category,
            rootURL: rootURL,
            displayName: displayName,
            explanation: explanation,
            minimumAge: minimumAge,
            maximumDepth: maximumDepth,
            maximumEntryCount: maximumEntryCount,
            risk: risk,
            relatedBundleIdentifier: relatedBundleIdentifier,
            requiresApplicationExit: requiresApplicationExit
        )
    }
}

public struct FileFingerprint: Hashable, Sendable {
    public let fileIdentifier: String
    public let volumeIdentifier: String
    public let modifiedAt: Date
    public let logicalSizeBytes: UInt64
    public let allocatedSizeBytes: UInt64
    public let isDirectory: Bool

    init(
        fileIdentifier: String,
        volumeIdentifier: String,
        modifiedAt: Date,
        logicalSizeBytes: UInt64,
        allocatedSizeBytes: UInt64,
        isDirectory: Bool
    ) {
        self.fileIdentifier = fileIdentifier
        self.volumeIdentifier = volumeIdentifier
        self.modifiedAt = modifiedAt
        self.logicalSizeBytes = logicalSizeBytes
        self.allocatedSizeBytes = allocatedSizeBytes
        self.isDirectory = isDirectory
    }
}

public struct TrustedRootFingerprint: Hashable, Sendable {
    public let fileIdentifier: String
    public let volumeIdentifier: String

    init(fileIdentifier: String, volumeIdentifier: String) {
        self.fileIdentifier = fileIdentifier
        self.volumeIdentifier = volumeIdentifier
    }
}

public struct CleanCandidate: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let ruleID: String
    public let ruleVersion: Int
    public let category: CleanCategory
    public let risk: CleanRisk
    public let url: URL
    public let allowedRootURL: URL
    public let rootFingerprint: TrustedRootFingerprint
    public let displayName: String
    public let explanation: String
    public let relatedBundleIdentifier: String?
    public let requiresApplicationExit: Bool
    public let fingerprint: FileFingerprint

    init(
        id: UUID = UUID(),
        ruleID: String,
        ruleVersion: Int,
        category: CleanCategory,
        risk: CleanRisk,
        url: URL,
        allowedRootURL: URL,
        rootFingerprint: TrustedRootFingerprint,
        displayName: String,
        explanation: String,
        relatedBundleIdentifier: String?,
        requiresApplicationExit: Bool,
        fingerprint: FileFingerprint
    ) {
        self.id = id
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.category = category
        self.risk = risk
        self.url = url.standardizedFileURL
        self.allowedRootURL = allowedRootURL.standardizedFileURL
        self.rootFingerprint = rootFingerprint
        self.displayName = displayName
        self.explanation = explanation
        self.relatedBundleIdentifier = relatedBundleIdentifier
        self.requiresApplicationExit = requiresApplicationExit
        self.fingerprint = fingerprint
    }
}

public enum ScanIssueKind: String, Codable, Sendable {
    case permissionDenied
    case unsafePath
    case changedDuringScan
    case unreadableMetadata
    case entryLimitExceeded
}

public struct ScanIssue: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let ruleID: String
    public let path: String
    public let kind: ScanIssueKind
    public let message: String

    init(
        id: UUID = UUID(),
        ruleID: String,
        path: String,
        kind: ScanIssueKind,
        message: String
    ) {
        self.id = id
        self.ruleID = ruleID
        self.path = path
        self.kind = kind
        self.message = message
    }
}

public struct CleanScanResult: Sendable {
    public let scannedAt: Date
    public let candidates: [CleanCandidate]
    public let issues: [ScanIssue]
    public let evaluatedRuleCount: Int

    init(
        scannedAt: Date,
        candidates: [CleanCandidate],
        issues: [ScanIssue],
        evaluatedRuleCount: Int
    ) {
        self.scannedAt = scannedAt
        self.candidates = candidates
        self.issues = issues
        self.evaluatedRuleCount = evaluatedRuleCount
    }
}

public struct CleanupPlan: Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let candidates: [CleanCandidate]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        candidates: [CleanCandidate]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.candidates = candidates
    }
}

public enum CleanupFailureReason: String, Codable, Sendable {
    case ruleMismatch
    case outsideAllowedRoot
    case symbolicLink
    case identityChanged
    case metadataChanged
    case unsupportedItem
    case applicationRunning
    case permissionDenied
    case noLongerExists
    case operationFailed
    case cancelled
}

public struct TrashedItem: Identifiable, Sendable {
    public let id: UUID
    public let candidateID: UUID
    public let originalURL: URL
    public let resultingTrashURL: URL?
    public let estimatedAllocatedBytes: UInt64

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        originalURL: URL,
        resultingTrashURL: URL?,
        estimatedAllocatedBytes: UInt64
    ) {
        self.id = id
        self.candidateID = candidateID
        self.originalURL = originalURL
        self.resultingTrashURL = resultingTrashURL
        self.estimatedAllocatedBytes = estimatedAllocatedBytes
    }
}

public struct CleanupItemFailure: Identifiable, Sendable {
    public let id: UUID
    public let candidateID: UUID
    public let displayName: String
    public let reason: CleanupFailureReason
    public let message: String

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        displayName: String,
        reason: CleanupFailureReason,
        message: String
    ) {
        self.id = id
        self.candidateID = candidateID
        self.displayName = displayName
        self.reason = reason
        self.message = message
    }
}

public struct UncertainCleanupMutation: Identifiable, Sendable {
    public let id: UUID
    public let candidateID: UUID
    public let originalURL: URL
    public let lastKnownTrashURL: URL?
    public let estimatedAllocatedBytes: UInt64

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        originalURL: URL,
        lastKnownTrashURL: URL?,
        estimatedAllocatedBytes: UInt64
    ) {
        self.id = id
        self.candidateID = candidateID
        self.originalURL = originalURL
        self.lastKnownTrashURL = lastKnownTrashURL
        self.estimatedAllocatedBytes = estimatedAllocatedBytes
    }
}

public struct CleanupExecutionResult: Sendable {
    public let planID: UUID
    public let finishedAt: Date
    public let trashedItems: [TrashedItem]
    public let uncertainMutations: [UncertainCleanupMutation]
    public let failures: [CleanupItemFailure]

    init(
        planID: UUID,
        finishedAt: Date,
        trashedItems: [TrashedItem],
        uncertainMutations: [UncertainCleanupMutation],
        failures: [CleanupItemFailure]
    ) {
        self.planID = planID
        self.finishedAt = finishedAt
        self.trashedItems = trashedItems
        self.uncertainMutations = uncertainMutations
        self.failures = failures
    }

    public var estimatedMovedBytes: UInt64 {
        trashedItems.reduce(into: 0) { total, item in
            let (next, overflow) = total.addingReportingOverflow(
                item.estimatedAllocatedBytes
            )
            total = overflow ? UInt64.max : next
        }
    }
}
