import Foundation

/// Samples aggregate system memory without parsing shell output or obtaining
/// task ports for other processes.
public actor SystemMemorySampler {
    private let provider: any MemorySystemProviding
    private let now: @Sendable () -> Date

    public init() {
        self.provider = DarwinMemorySystemProvider()
        self.now = Date.init
    }

    init(
        provider: any MemorySystemProviding,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.now = now
    }

    /// Returns the best sample available at the time of the call.
    ///
    /// Failures are represented by optional fields and `samplingQuality` so a
    /// transient Mach or sysctl failure does not take down the monitoring UI.
    public func sample() -> MemorySnapshot {
        let physicalMemoryBytes = provider.physicalMemoryBytes

        var pageSizeBytes: UInt64?
        var pageCounts: VirtualMemoryPageCounts?
        var swapUsage: SwapUsageBytes?

        do {
            let sampledPageSize = try provider.pageSizeBytes()
            pageSizeBytes = sampledPageSize > 0 ? sampledPageSize : nil
        } catch {
            pageSizeBytes = nil
        }

        do {
            pageCounts = try provider.virtualMemoryPageCounts()
        } catch {
            pageCounts = nil
        }

        do {
            swapUsage = try provider.swapUsageBytes()
        } catch {
            swapUsage = nil
        }

        let pageValues = MemoryByteValues(
            pageCounts: pageCounts,
            pageSizeBytes: pageSizeBytes
        )
        let pressure = MemoryPressureEstimator.estimate(
            physicalMemoryBytes: physicalMemoryBytes,
            freeMemoryBytes: pageValues.free,
            inactiveMemoryBytes: pageValues.inactive,
            speculativeMemoryBytes: pageValues.speculative,
            compressedMemoryBytes: pageValues.compressed,
            swapUsedBytes: swapUsage?.used
        )
        let quality = MemorySamplingQuality.assess(
            physicalMemoryBytes: physicalMemoryBytes,
            pageValues: pageValues,
            swapUsage: swapUsage
        )

        return MemorySnapshot(
            timestamp: now(),
            physicalMemoryBytes: physicalMemoryBytes,
            pageSizeBytes: pageSizeBytes,
            freeMemoryBytes: pageValues.free,
            activeMemoryBytes: pageValues.active,
            inactiveMemoryBytes: pageValues.inactive,
            wiredMemoryBytes: pageValues.wired,
            speculativeMemoryBytes: pageValues.speculative,
            purgeableMemoryBytes: pageValues.purgeable,
            compressedMemoryBytes: pageValues.compressed,
            fileBackedMemoryBytes: pageValues.fileBacked,
            anonymousMemoryBytes: pageValues.anonymous,
            swapUsedBytes: swapUsage?.used,
            swapAvailableBytes: swapUsage?.available,
            swapTotalBytes: swapUsage?.total,
            estimatedPressureLevel: pressure,
            samplingQuality: quality
        )
    }
}

enum MemoryByteMath {
    /// Converts page counts to bytes, rejecting invalid page sizes and
    /// arithmetic overflow instead of wrapping.
    static func pagesToBytes(pages: UInt64, pageSizeBytes: UInt64) -> UInt64? {
        guard pageSizeBytes > 0 else {
            return nil
        }

        let (bytes, overflow) = pages.multipliedReportingOverflow(
            by: pageSizeBytes
        )
        return overflow ? nil : bytes
    }

    /// Adds values while clamping to a known upper bound.
    static func sumClamped(_ values: [UInt64], upperBound: UInt64) -> UInt64 {
        var total: UInt64 = 0
        for value in values {
            let (sum, overflow) = total.addingReportingOverflow(value)
            if overflow || sum >= upperBound {
                return upperBound
            }
            total = sum
        }
        return min(total, upperBound)
    }
}

enum MemoryPressureEstimator {
    /// Produces a conservative heuristic from public VM counters.
    ///
    /// This is intentionally not named or presented as the macOS memory
    /// pressure value. Purgeable pages are excluded because they can overlap
    /// other VM queues. Historical swap can remain after pressure subsides, so
    /// swap and compression only raise a normal estimate to warning.
    static func estimate(
        physicalMemoryBytes: UInt64,
        freeMemoryBytes: UInt64?,
        inactiveMemoryBytes: UInt64?,
        speculativeMemoryBytes: UInt64?,
        compressedMemoryBytes: UInt64?,
        swapUsedBytes: UInt64?
    ) -> MemoryPressureLevel {
        guard physicalMemoryBytes > 0,
              let freeMemoryBytes,
              let inactiveMemoryBytes,
              let speculativeMemoryBytes,
              let compressedMemoryBytes
        else {
            return .unknown
        }

        let reclaimableBytes = MemoryByteMath.sumClamped(
            [
                freeMemoryBytes,
                inactiveMemoryBytes,
                speculativeMemoryBytes,
            ],
            upperBound: physicalMemoryBytes
        )
        let reclaimableRatio =
            Double(reclaimableBytes) / Double(physicalMemoryBytes)

        if reclaimableRatio <= 0.05 {
            return .critical
        }
        if reclaimableRatio <= 0.15 {
            return .warning
        }

        let compressedRatio =
            Double(min(compressedMemoryBytes, physicalMemoryBytes))
                / Double(physicalMemoryBytes)
        let swapRatio = Double(min(swapUsedBytes ?? 0, physicalMemoryBytes))
            / Double(physicalMemoryBytes)

        if compressedRatio >= 0.50 || swapRatio >= 0.25 {
            return .warning
        }
        return .normal
    }
}

private struct MemoryByteValues {
    let free: UInt64?
    let active: UInt64?
    let inactive: UInt64?
    let wired: UInt64?
    let speculative: UInt64?
    let purgeable: UInt64?
    let compressed: UInt64?
    let fileBacked: UInt64?
    let anonymous: UInt64?

    init(
        pageCounts: VirtualMemoryPageCounts?,
        pageSizeBytes: UInt64?
    ) {
        guard let pageCounts, let pageSizeBytes else {
            free = nil
            active = nil
            inactive = nil
            wired = nil
            speculative = nil
            purgeable = nil
            compressed = nil
            fileBacked = nil
            anonymous = nil
            return
        }

        free = MemoryByteMath.pagesToBytes(
            pages: pageCounts.free,
            pageSizeBytes: pageSizeBytes
        )
        active = MemoryByteMath.pagesToBytes(
            pages: pageCounts.active,
            pageSizeBytes: pageSizeBytes
        )
        inactive = MemoryByteMath.pagesToBytes(
            pages: pageCounts.inactive,
            pageSizeBytes: pageSizeBytes
        )
        wired = MemoryByteMath.pagesToBytes(
            pages: pageCounts.wired,
            pageSizeBytes: pageSizeBytes
        )
        speculative = MemoryByteMath.pagesToBytes(
            pages: pageCounts.speculative,
            pageSizeBytes: pageSizeBytes
        )
        purgeable = MemoryByteMath.pagesToBytes(
            pages: pageCounts.purgeable,
            pageSizeBytes: pageSizeBytes
        )
        compressed = MemoryByteMath.pagesToBytes(
            pages: pageCounts.compressed,
            pageSizeBytes: pageSizeBytes
        )
        fileBacked = MemoryByteMath.pagesToBytes(
            pages: pageCounts.fileBacked,
            pageSizeBytes: pageSizeBytes
        )
        anonymous = MemoryByteMath.pagesToBytes(
            pages: pageCounts.anonymous,
            pageSizeBytes: pageSizeBytes
        )
    }

    var hasAllValues: Bool {
        free != nil
            && active != nil
            && inactive != nil
            && wired != nil
            && speculative != nil
            && purgeable != nil
            && compressed != nil
            && fileBacked != nil
            && anonymous != nil
    }

    var hasAnyValue: Bool {
        free != nil
            || active != nil
            || inactive != nil
            || wired != nil
            || speculative != nil
            || purgeable != nil
            || compressed != nil
            || fileBacked != nil
            || anonymous != nil
    }
}

private extension MemorySamplingQuality {
    static func assess(
        physicalMemoryBytes: UInt64,
        pageValues: MemoryByteValues,
        swapUsage: SwapUsageBytes?
    ) -> MemorySamplingQuality {
        if physicalMemoryBytes > 0,
           pageValues.hasAllValues,
           swapUsage != nil
        {
            return .complete
        }

        if physicalMemoryBytes > 0
            || pageValues.hasAnyValue
            || swapUsage != nil
        {
            return .partial
        }
        return .unavailable
    }
}
