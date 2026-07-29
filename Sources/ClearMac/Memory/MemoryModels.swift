import Foundation

/// A coarse, estimated view of system memory pressure.
///
/// ClearMac does not attempt to reproduce Activity Monitor's private memory
/// pressure calculation. Callers should present this value as an estimate.
public enum MemoryPressureLevel: String, Codable, CaseIterable, Sendable {
    case unknown
    case normal
    case warning
    case critical
}

/// Describes how much of a memory sample was available.
public enum MemorySamplingQuality: String, Codable, CaseIterable, Sendable {
    /// Physical memory, VM page statistics, and swap usage were all sampled.
    case complete

    /// At least one useful source was sampled, but one or more sources failed.
    case partial

    /// No useful source was available.
    case unavailable
}

/// A point-in-time sample of system-wide memory information.
///
/// Page-backed values are optional because Mach calls can fail independently
/// from `ProcessInfo` and `sysctl`. All sizes are expressed in bytes.
public struct MemorySnapshot: Equatable, Sendable {
    public let timestamp: Date
    public let physicalMemoryBytes: UInt64
    public let pageSizeBytes: UInt64?

    public let freeMemoryBytes: UInt64?
    public let activeMemoryBytes: UInt64?
    public let inactiveMemoryBytes: UInt64?
    public let wiredMemoryBytes: UInt64?
    public let speculativeMemoryBytes: UInt64?
    public let purgeableMemoryBytes: UInt64?
    public let compressedMemoryBytes: UInt64?
    public let fileBackedMemoryBytes: UInt64?
    public let anonymousMemoryBytes: UInt64?

    public let swapUsedBytes: UInt64?
    public let swapAvailableBytes: UInt64?
    public let swapTotalBytes: UInt64?

    /// A ClearMac heuristic, not Activity Monitor's memory-pressure value.
    public let estimatedPressureLevel: MemoryPressureLevel
    public let samplingQuality: MemorySamplingQuality

    public init(
        timestamp: Date,
        physicalMemoryBytes: UInt64,
        pageSizeBytes: UInt64?,
        freeMemoryBytes: UInt64?,
        activeMemoryBytes: UInt64?,
        inactiveMemoryBytes: UInt64?,
        wiredMemoryBytes: UInt64?,
        speculativeMemoryBytes: UInt64?,
        purgeableMemoryBytes: UInt64?,
        compressedMemoryBytes: UInt64?,
        fileBackedMemoryBytes: UInt64?,
        anonymousMemoryBytes: UInt64?,
        swapUsedBytes: UInt64?,
        swapAvailableBytes: UInt64?,
        swapTotalBytes: UInt64?,
        estimatedPressureLevel: MemoryPressureLevel,
        samplingQuality: MemorySamplingQuality
    ) {
        self.timestamp = timestamp
        self.physicalMemoryBytes = physicalMemoryBytes
        self.pageSizeBytes = pageSizeBytes
        self.freeMemoryBytes = freeMemoryBytes
        self.activeMemoryBytes = activeMemoryBytes
        self.inactiveMemoryBytes = inactiveMemoryBytes
        self.wiredMemoryBytes = wiredMemoryBytes
        self.speculativeMemoryBytes = speculativeMemoryBytes
        self.purgeableMemoryBytes = purgeableMemoryBytes
        self.compressedMemoryBytes = compressedMemoryBytes
        self.fileBackedMemoryBytes = fileBackedMemoryBytes
        self.anonymousMemoryBytes = anonymousMemoryBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapAvailableBytes = swapAvailableBytes
        self.swapTotalBytes = swapTotalBytes
        self.estimatedPressureLevel = estimatedPressureLevel
        self.samplingQuality = samplingQuality
    }
}
