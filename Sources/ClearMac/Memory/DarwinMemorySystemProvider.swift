import Darwin
import Foundation

struct DarwinMemorySystemProvider: MemorySystemProviding {
    var physicalMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    func pageSizeBytes() throws -> UInt64 {
        try withHostPort { hostPort in
            var pageSize: vm_size_t = 0
            let result = host_page_size(hostPort, &pageSize)

            guard result == KERN_SUCCESS else {
                throw MemorySystemError.machCallFailed(
                    operation: "host_page_size",
                    code: result
                )
            }

            let value = UInt64(pageSize)
            guard value > 0 else {
                throw MemorySystemError.invalidPageSize(value)
            }
            return value
        }
    }

    func virtualMemoryPageCounts() throws -> VirtualMemoryPageCounts {
        try withHostPort { hostPort in
            var statistics = vm_statistics64_data_t()
            let expectedCount = mach_msg_type_number_t(
                MemoryLayout<vm_statistics64_data_t>.stride
                    / MemoryLayout<integer_t>.stride
            )
            var count = expectedCount

            let result = withUnsafeMutablePointer(to: &statistics) { pointer in
                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity: Int(expectedCount)
                ) { reboundPointer in
                    host_statistics64(
                        hostPort,
                        HOST_VM_INFO64,
                        reboundPointer,
                        &count
                    )
                }
            }

            guard result == KERN_SUCCESS else {
                throw MemorySystemError.machCallFailed(
                    operation: "host_statistics64",
                    code: result
                )
            }
            guard count >= expectedCount else {
                throw MemorySystemError.unexpectedResultSize(
                    operation: "host_statistics64",
                    expected: Int(expectedCount),
                    actual: Int(count)
                )
            }

            return VirtualMemoryPageCounts(
                free: UInt64(statistics.free_count),
                active: UInt64(statistics.active_count),
                inactive: UInt64(statistics.inactive_count),
                wired: UInt64(statistics.wire_count),
                speculative: UInt64(statistics.speculative_count),
                purgeable: UInt64(statistics.purgeable_count),
                compressed: UInt64(statistics.compressor_page_count),
                fileBacked: UInt64(statistics.external_page_count),
                anonymous: UInt64(statistics.internal_page_count)
            )
        }
    }

    func swapUsageBytes() throws -> SwapUsageBytes {
        var usage = xsw_usage()
        let expectedSize = MemoryLayout<xsw_usage>.stride
        var size = expectedSize

        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else {
            throw MemorySystemError.posixCallFailed(
                operation: "sysctlbyname(vm.swapusage)",
                code: errno
            )
        }
        guard size >= expectedSize else {
            throw MemorySystemError.unexpectedResultSize(
                operation: "sysctlbyname(vm.swapusage)",
                expected: expectedSize,
                actual: size
            )
        }

        return SwapUsageBytes(
            used: usage.xsu_used,
            available: usage.xsu_avail,
            total: usage.xsu_total
        )
    }

    private func withHostPort<Value>(
        _ operation: (host_t) throws -> Value
    ) rethrows -> Value {
        let hostPort = mach_host_self()
        defer {
            _ = mach_port_deallocate(mach_task_self_, hostPort)
        }
        return try operation(hostPort)
    }
}
