import Foundation
import XCTest

@testable import ClearMac

final class SystemMemorySamplerTests: XCTestCase {
    func testSampleConvertsPagesAndIncludesSwapUsage() async {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = StubMemorySystemProvider(
            physicalMemoryBytes: 1_000,
            pageSizeResult: .success(10),
            pageCountsResult: .success(
                VirtualMemoryPageCounts(
                    free: 20,
                    active: 30,
                    inactive: 10,
                    wired: 15,
                    speculative: 5,
                    purgeable: 4,
                    compressed: 8,
                    fileBacked: 12,
                    anonymous: 25
                )
            ),
            swapUsageResult: .success(
                SwapUsageBytes(used: 50, available: 150, total: 200)
            )
        )
        let sampler = SystemMemorySampler(
            provider: provider,
            now: { timestamp }
        )

        let snapshot = await sampler.sample()

        XCTAssertEqual(snapshot.timestamp, timestamp)
        XCTAssertEqual(snapshot.physicalMemoryBytes, 1_000)
        XCTAssertEqual(snapshot.pageSizeBytes, 10)
        XCTAssertEqual(snapshot.freeMemoryBytes, 200)
        XCTAssertEqual(snapshot.activeMemoryBytes, 300)
        XCTAssertEqual(snapshot.inactiveMemoryBytes, 100)
        XCTAssertEqual(snapshot.wiredMemoryBytes, 150)
        XCTAssertEqual(snapshot.speculativeMemoryBytes, 50)
        XCTAssertEqual(snapshot.purgeableMemoryBytes, 40)
        XCTAssertEqual(snapshot.compressedMemoryBytes, 80)
        XCTAssertEqual(snapshot.fileBackedMemoryBytes, 120)
        XCTAssertEqual(snapshot.anonymousMemoryBytes, 250)
        XCTAssertEqual(snapshot.swapUsedBytes, 50)
        XCTAssertEqual(snapshot.swapAvailableBytes, 150)
        XCTAssertEqual(snapshot.swapTotalBytes, 200)
        XCTAssertEqual(snapshot.estimatedPressureLevel, .normal)
        XCTAssertEqual(snapshot.samplingQuality, .complete)
    }

    func testPageFailureStillReturnsPhysicalMemoryAndSwap() async {
        let provider = StubMemorySystemProvider(
            physicalMemoryBytes: 16_000,
            pageSizeResult: .failure(.fixture),
            pageCountsResult: .failure(.fixture),
            swapUsageResult: .success(
                SwapUsageBytes(used: 1, available: 9, total: 10)
            )
        )
        let sampler = SystemMemorySampler(provider: provider)

        let snapshot = await sampler.sample()

        XCTAssertEqual(snapshot.physicalMemoryBytes, 16_000)
        XCTAssertNil(snapshot.pageSizeBytes)
        XCTAssertNil(snapshot.freeMemoryBytes)
        XCTAssertEqual(snapshot.swapUsedBytes, 1)
        XCTAssertEqual(snapshot.estimatedPressureLevel, .unknown)
        XCTAssertEqual(snapshot.samplingQuality, .partial)
    }

    func testPageCountFailurePreservesKnownRuntimePageSize() async {
        let provider = StubMemorySystemProvider(
            physicalMemoryBytes: 16_000,
            pageSizeResult: .success(16_384),
            pageCountsResult: .failure(.fixture),
            swapUsageResult: .success(
                SwapUsageBytes(used: 1, available: 9, total: 10)
            )
        )
        let sampler = SystemMemorySampler(provider: provider)

        let snapshot = await sampler.sample()

        XCTAssertEqual(snapshot.pageSizeBytes, 16_384)
        XCTAssertNil(snapshot.freeMemoryBytes)
        XCTAssertEqual(snapshot.samplingQuality, .partial)
    }

    func testSwapFailureLeavesUsablePageSampleMarkedPartial() async {
        let provider = StubMemorySystemProvider(
            physicalMemoryBytes: 1_000,
            pageSizeResult: .success(10),
            pageCountsResult: .success(
                VirtualMemoryPageCounts(
                    free: 2,
                    active: 70,
                    inactive: 2,
                    wired: 10,
                    speculative: 1,
                    purgeable: 0,
                    compressed: 15,
                    fileBacked: 20,
                    anonymous: 50
                )
            ),
            swapUsageResult: .failure(.fixture)
        )
        let sampler = SystemMemorySampler(provider: provider)

        let snapshot = await sampler.sample()

        XCTAssertEqual(snapshot.estimatedPressureLevel, .critical)
        XCTAssertNil(snapshot.swapUsedBytes)
        XCTAssertEqual(snapshot.samplingQuality, .partial)
    }

    func testArithmeticOverflowDoesNotWrapSnapshotValues() async {
        let provider = StubMemorySystemProvider(
            physicalMemoryBytes: UInt64.max,
            pageSizeResult: .success(2),
            pageCountsResult: .success(
                VirtualMemoryPageCounts(
                    free: UInt64.max,
                    active: 1,
                    inactive: 1,
                    wired: 1,
                    speculative: 1,
                    purgeable: 1,
                    compressed: 1,
                    fileBacked: 1,
                    anonymous: 1
                )
            ),
            swapUsageResult: .success(
                SwapUsageBytes(used: 0, available: 0, total: 0)
            )
        )
        let sampler = SystemMemorySampler(provider: provider)

        let snapshot = await sampler.sample()

        XCTAssertNil(snapshot.freeMemoryBytes)
        XCTAssertEqual(snapshot.activeMemoryBytes, 2)
        XCTAssertEqual(snapshot.estimatedPressureLevel, .unknown)
        XCTAssertEqual(snapshot.samplingQuality, .partial)
    }

    func testNoUsefulSourcesIsUnavailable() async {
        let provider = StubMemorySystemProvider(
            physicalMemoryBytes: 0,
            pageSizeResult: .failure(.fixture),
            pageCountsResult: .failure(.fixture),
            swapUsageResult: .failure(.fixture)
        )
        let sampler = SystemMemorySampler(provider: provider)

        let snapshot = await sampler.sample()

        XCTAssertEqual(snapshot.samplingQuality, .unavailable)
        XCTAssertEqual(snapshot.estimatedPressureLevel, .unknown)
    }
}

final class MemoryByteMathTests: XCTestCase {
    func testPagesToBytesHandlesZeroAndExactUpperBoundary() {
        XCTAssertEqual(
            MemoryByteMath.pagesToBytes(pages: 0, pageSizeBytes: 16_384),
            0
        )
        XCTAssertEqual(
            MemoryByteMath.pagesToBytes(
                pages: UInt64.max,
                pageSizeBytes: 1
            ),
            UInt64.max
        )
    }

    func testPagesToBytesRejectsZeroPageSizeAndOverflow() {
        XCTAssertNil(
            MemoryByteMath.pagesToBytes(pages: 1, pageSizeBytes: 0)
        )
        XCTAssertNil(
            MemoryByteMath.pagesToBytes(
                pages: UInt64.max,
                pageSizeBytes: 2
            )
        )
    }

    func testClampedSumDoesNotOverflow() {
        XCTAssertEqual(
            MemoryByteMath.sumClamped(
                [UInt64.max - 1, 10],
                upperBound: UInt64.max
            ),
            UInt64.max
        )
        XCTAssertEqual(
            MemoryByteMath.sumClamped([10, 20], upperBound: 25),
            25
        )
    }
}

final class MemoryPressureEstimatorTests: XCTestCase {
    func testPressureBoundaries() {
        XCTAssertEqual(
            estimate(reclaimableBytes: 151),
            .normal
        )
        XCTAssertEqual(
            estimate(reclaimableBytes: 150),
            .warning
        )
        XCTAssertEqual(
            estimate(reclaimableBytes: 51),
            .warning
        )
        XCTAssertEqual(
            estimate(reclaimableBytes: 50),
            .critical
        )
    }

    func testHighCompressionOrSwapOnlyRaisesEstimateToWarning() {
        XCTAssertEqual(
            estimate(
                reclaimableBytes: 500,
                compressedBytes: 500
            ),
            .warning
        )
        XCTAssertEqual(
            estimate(
                reclaimableBytes: 500,
                swapUsedBytes: 250
            ),
            .warning
        )
    }

    func testMissingCoreMetricProducesUnknownPressure() {
        XCTAssertEqual(
            MemoryPressureEstimator.estimate(
                physicalMemoryBytes: 1_000,
                freeMemoryBytes: nil,
                inactiveMemoryBytes: 100,
                speculativeMemoryBytes: 100,
                compressedMemoryBytes: 100,
                swapUsedBytes: 0
            ),
            .unknown
        )
    }

    func testSpeculativePagesAreNotAddedToFreePagesAgain() {
        XCTAssertEqual(
            MemoryPressureEstimator.estimate(
                physicalMemoryBytes: 1_000,
                freeMemoryBytes: 50,
                inactiveMemoryBytes: 0,
                speculativeMemoryBytes: 100,
                compressedMemoryBytes: 0,
                swapUsedBytes: 0
            ),
            .critical
        )
    }

    private func estimate(
        reclaimableBytes: UInt64,
        compressedBytes: UInt64 = 0,
        swapUsedBytes: UInt64 = 0
    ) -> MemoryPressureLevel {
        MemoryPressureEstimator.estimate(
            physicalMemoryBytes: 1_000,
            freeMemoryBytes: reclaimableBytes,
            inactiveMemoryBytes: 0,
            speculativeMemoryBytes: 0,
            compressedMemoryBytes: compressedBytes,
            swapUsedBytes: swapUsedBytes
        )
    }
}

private enum StubError: Error, Sendable {
    case fixture
}

private struct StubMemorySystemProvider: MemorySystemProviding {
    let physicalMemoryBytes: UInt64
    let pageSizeResult: Result<UInt64, StubError>
    let pageCountsResult: Result<VirtualMemoryPageCounts, StubError>
    let swapUsageResult: Result<SwapUsageBytes, StubError>

    func pageSizeBytes() throws -> UInt64 {
        try pageSizeResult.get()
    }

    func virtualMemoryPageCounts() throws -> VirtualMemoryPageCounts {
        try pageCountsResult.get()
    }

    func swapUsageBytes() throws -> SwapUsageBytes {
        try swapUsageResult.get()
    }
}
