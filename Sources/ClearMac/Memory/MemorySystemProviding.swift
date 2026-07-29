import Foundation

/// Raw VM counters returned by the system. Values are page counts, not bytes.
struct VirtualMemoryPageCounts: Equatable, Sendable {
    let free: UInt64
    let active: UInt64
    let inactive: UInt64
    let wired: UInt64
    let speculative: UInt64
    let purgeable: UInt64
    let compressed: UInt64
    let fileBacked: UInt64
    let anonymous: UInt64
}

struct SwapUsageBytes: Equatable, Sendable {
    let used: UInt64
    let available: UInt64
    let total: UInt64
}

/// Injectable boundary around the macOS APIs used by `SystemMemorySampler`.
///
/// It is intentionally internal: production callers use
/// `SystemMemorySampler.init()`, while tests can inject deterministic values
/// through `@testable import ClearMac`.
protocol MemorySystemProviding: Sendable {
    var physicalMemoryBytes: UInt64 { get }

    func pageSizeBytes() throws -> UInt64
    func virtualMemoryPageCounts() throws -> VirtualMemoryPageCounts
    func swapUsageBytes() throws -> SwapUsageBytes
}

enum MemorySystemError: Error, Equatable, Sendable {
    case machCallFailed(operation: String, code: Int32)
    case posixCallFailed(operation: String, code: Int32)
    case invalidPageSize(UInt64)
    case unexpectedResultSize(operation: String, expected: Int, actual: Int)
}
