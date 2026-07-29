import Darwin
import Foundation

struct CleanupFileMetadata: Equatable, Sendable {
    let isDirectory: Bool
    let isRegularFile: Bool
    let isSymbolicLink: Bool
    let isVolume: Bool
    let modifiedAt: Date?
    let fileIdentifier: String?
    let volumeIdentifier: String?
    let logicalSizeBytes: UInt64
    let allocatedSizeBytes: UInt64
}

struct CleanupDirectoryListing: Sendable {
    let entries: [URL]
    let reachedLimit: Bool
}

struct UnverifiedMoveDetails: Sendable {
    let lastKnownTrashURL: URL?
    let verificationErrorCode: Int32?
    let restorationErrorCode: Int32?
}

enum SecureTrashMoveError: Error, Sendable {
    case invalidPath
    case rootChanged
    case ancestorChanged
    case sourceChanged
    case unsupportedSource
    case trashUnavailable
    case differentVolume
    case movedButUnverified(UnverifiedMoveDetails)
    case posix(operation: String, code: Int32)
}

protocol CleanupFileSystem: Sendable {
    func metadata(at url: URL) async throws -> CleanupFileMetadata
    func children(
        of url: URL,
        limit: Int
    ) async throws -> CleanupDirectoryListing
    func securelyMoveToTrash(
        _ candidate: CleanCandidate
    ) async throws -> URL
}

struct LocalCleanupFileSystem: CleanupFileSystem {
    private let trashDirectoryOverride: URL?
    private let trashDirectoryOpenedHook:
        (@Sendable () throws -> Void)?

    init(
        trashDirectoryOverride: URL? = nil,
        trashDirectoryOpenedHook:
            (@Sendable () throws -> Void)? = nil
    ) {
        self.trashDirectoryOverride = trashDirectoryOverride
        self.trashDirectoryOpenedHook = trashDirectoryOpenedHook
    }

    func metadata(at url: URL) async throws -> CleanupFileMetadata {
        let components = try Self.absoluteComponents(for: url)
        guard let leafName = components.last else {
            let rootFD = try Self.openDirectory(
                components: [],
                operation: "open filesystem root"
            )
            defer { close(rootFD) }

            var rootStatus = stat()
            guard fstat(rootFD, &rootStatus) == 0 else {
                throw SecureTrashMoveError.posix(
                    operation: "fstat filesystem root",
                    code: errno
                )
            }
            return Self.metadata(from: rootStatus, isVolume: true)
        }

        let parentFD = try Self.openDirectory(
            components: Array(components.dropLast()),
            operation: "open metadata parent"
        )
        defer { close(parentFD) }

        var parentStatus = stat()
        guard fstat(parentFD, &parentStatus) == 0 else {
            throw SecureTrashMoveError.posix(
                operation: "fstat metadata parent",
                code: errno
            )
        }

        var status = stat()
        let result = leafName.withCString { pointer in
            fstatat(
                parentFD,
                pointer,
                &status,
                AT_SYMLINK_NOFOLLOW
            )
        }
        guard result == 0 else {
            throw SecureTrashMoveError.posix(
                operation: "fstatat metadata",
                code: errno
            )
        }

        return Self.metadata(
            from: status,
            isVolume: Self.isDirectory(status)
                && status.st_dev != parentStatus.st_dev
        )
    }

    func children(
        of url: URL,
        limit: Int
    ) async throws -> CleanupDirectoryListing {
        guard limit > 0 else {
            return CleanupDirectoryListing(
                entries: [],
                reachedLimit: true
            )
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) else {
            throw SecureTrashMoveError.invalidPath
        }

        var entries: [URL] = []
        entries.reserveCapacity(min(limit, 1_024))

        while let entry = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard entries.count < limit else {
                return CleanupDirectoryListing(
                    entries: entries,
                    reachedLimit: true
                )
            }
            entries.append(entry)
        }

        return CleanupDirectoryListing(
            entries: entries,
            reachedLimit: false
        )
    }

    /// Moves one regular file to the current user's Trash using directory file
    /// descriptors. Every relative path lookup is anchored to an already-open,
    /// non-symlink directory, so swapping an ancestor pathname cannot redirect
    /// the mutation outside the trusted rule root.
    func securelyMoveToTrash(
        _ candidate: CleanCandidate
    ) async throws -> URL {
        try Task.checkCancellation()

        let components = try Self.relativeComponents(
            of: candidate.url,
            under: candidate.allowedRootURL
        )
        guard let leafName = components.last else {
            throw SecureTrashMoveError.invalidPath
        }

        let rootFD = try Self.openDirectory(
            candidate.allowedRootURL,
            operation: "open trusted root"
        )
        defer { close(rootFD) }

        var rootStatus = stat()
        guard fstat(rootFD, &rootStatus) == 0 else {
            throw SecureTrashMoveError.posix(
                operation: "fstat trusted root",
                code: errno
            )
        }
        guard
            Self.fileIdentifier(rootStatus)
                == candidate.rootFingerprint.fileIdentifier,
            Self.volumeIdentifier(rootStatus)
                == candidate.rootFingerprint.volumeIdentifier
        else {
            throw SecureTrashMoveError.rootChanged
        }

        var openedDirectoryFDs: [Int32] = []
        defer {
            for descriptor in openedDirectoryFDs.reversed() {
                close(descriptor)
            }
        }

        var parentFD = rootFD
        var sourceParentStatus = rootStatus
        for component in components.dropLast() {
            let descriptor = try Self.openDirectory(
                named: component,
                relativeTo: parentFD
            )
            var status = stat()
            guard fstat(descriptor, &status) == 0 else {
                close(descriptor)
                throw SecureTrashMoveError.posix(
                    operation: "fstat ancestor",
                    code: errno
                )
            }
            guard Self.isDirectory(status),
                  Self.volumeIdentifier(status)
                    == candidate.rootFingerprint.volumeIdentifier
            else {
                close(descriptor)
                throw SecureTrashMoveError.ancestorChanged
            }
            openedDirectoryFDs.append(descriptor)
            parentFD = descriptor
            sourceParentStatus = status
        }
        let sourceParentURL = candidate.url.deletingLastPathComponent()

        let sourceFD = leafName.withCString { leafPointer in
            openat(
                parentFD,
                leafPointer,
                O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
            )
        }
        guard sourceFD >= 0 else {
            throw SecureTrashMoveError.posix(
                operation: "openat source",
                code: errno
            )
        }
        defer { close(sourceFD) }

        // Holding the original file descriptor prevents its inode from being
        // recycled while the pathname is revalidated and moved.
        var sourceStatus = stat()
        guard fstat(sourceFD, &sourceStatus) == 0 else {
            throw SecureTrashMoveError.posix(
                operation: "fstat source",
                code: errno
            )
        }
        try Self.validate(sourceStatus, against: candidate.fingerprint)

        let trashDirectory = trashDirectoryOverride
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash", isDirectory: true)
        let trashFD = try Self.openDirectory(
            trashDirectory,
            operation: "open Trash"
        )
        defer { close(trashFD) }

        var trashStatus = stat()
        guard fstat(trashFD, &trashStatus) == 0,
              Self.isDirectory(trashStatus),
              trashStatus.st_uid == getuid()
        else {
            throw SecureTrashMoveError.trashUnavailable
        }
        guard trashStatus.st_dev == rootStatus.st_dev else {
            throw SecureTrashMoveError.differentVolume
        }

        try trashDirectoryOpenedHook?()
        try Task.checkCancellation()
        guard try Self.directoryIdentityMatches(
            sourceParentURL,
            expectedStatus: sourceParentStatus
        ) else {
            throw SecureTrashMoveError.ancestorChanged
        }

        var destinationName = leafName
        var renameResult = Self.renameExclusively(
            from: parentFD,
            sourceName: leafName,
            to: trashFD,
            destinationName: destinationName
        )
        if renameResult != 0, errno == EEXIST {
            destinationName = Self.collisionSafeTrashName(
                for: leafName
            )
            renameResult = Self.renameExclusively(
                from: parentFD,
                sourceName: leafName,
                to: trashFD,
                destinationName: destinationName
            )
        }
        guard renameResult == 0 else {
            throw SecureTrashMoveError.posix(
                operation: "renameatx_np",
                code: errno
            )
        }

        let expectedTrashURL = trashDirectory.appendingPathComponent(
            destinationName
        )
        var movedStatus = stat()
        let movedResult = destinationName.withCString { destinationPointer in
            fstatat(
                trashFD,
                destinationPointer,
                &movedStatus,
                AT_SYMLINK_NOFOLLOW
            )
        }
        guard movedResult == 0 else {
            // The mutation has already happened. Even if another process
            // immediately moves the item again, report the source as moved
            // instead of presenting this as an ordinary pre-mutation failure.
            throw SecureTrashMoveError.movedButUnverified(
                UnverifiedMoveDetails(
                    lastKnownTrashURL: nil,
                    verificationErrorCode: errno,
                    restorationErrorCode: nil
                )
            )
        }
        do {
            try Self.validate(
                movedStatus,
                against: candidate.fingerprint
            )
        } catch let validationError {
            let restoreResult = destinationName.withCString {
                destinationPointer in
                leafName.withCString { sourcePointer in
                    renameatx_np(
                        trashFD,
                        destinationPointer,
                        parentFD,
                        sourcePointer,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            if restoreResult != 0 {
                throw SecureTrashMoveError.movedButUnverified(
                    UnverifiedMoveDetails(
                        lastKnownTrashURL: nil,
                        verificationErrorCode: nil,
                        restorationErrorCode: errno
                    )
                )
            }
            do {
                try Self.verifyRestoredSource(
                    named: leafName,
                    in: parentFD,
                    parentURL: sourceParentURL,
                    expectedParentStatus: sourceParentStatus,
                    fingerprint: candidate.fingerprint
                )
            } catch {
                throw SecureTrashMoveError.movedButUnverified(
                    UnverifiedMoveDetails(
                        lastKnownTrashURL: nil,
                        verificationErrorCode: Self.posixCode(from: error),
                        restorationErrorCode: nil
                    )
                )
            }
            throw validationError
        }

        do {
            guard try Self.directoryIdentityMatches(
                trashDirectory,
                expectedStatus: trashStatus
            ) else {
                throw SecureTrashMoveError.trashUnavailable
            }
        } catch {
            let verificationErrorCode = Self.posixCode(from: error)
            let restoreResult = destinationName.withCString {
                destinationPointer in
                leafName.withCString { sourcePointer in
                    renameatx_np(
                        trashFD,
                        destinationPointer,
                        parentFD,
                        sourcePointer,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard restoreResult == 0 else {
                throw SecureTrashMoveError.movedButUnverified(
                    UnverifiedMoveDetails(
                        lastKnownTrashURL: nil,
                        verificationErrorCode: verificationErrorCode,
                        restorationErrorCode: errno
                    )
                )
            }
            do {
                try Self.verifyRestoredSource(
                    named: leafName,
                    in: parentFD,
                    parentURL: sourceParentURL,
                    expectedParentStatus: sourceParentStatus,
                    fingerprint: candidate.fingerprint
                )
            } catch {
                throw SecureTrashMoveError.movedButUnverified(
                    UnverifiedMoveDetails(
                        lastKnownTrashURL: nil,
                        verificationErrorCode: Self.posixCode(from: error),
                        restorationErrorCode: nil
                    )
                )
            }
            throw error
        }

        return expectedTrashURL
    }

    private static func relativeComponents(
        of candidate: URL,
        under root: URL
    ) throws -> [String] {
        guard PathSafetyPolicy.isStrictDescendant(candidate, of: root) else {
            throw SecureTrashMoveError.invalidPath
        }
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let relative = Array(candidateComponents.dropFirst(rootComponents.count))

        guard !relative.isEmpty,
              relative.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/")
              })
        else {
            throw SecureTrashMoveError.invalidPath
        }
        return relative
    }

    private static func openDirectory(
        _ url: URL,
        operation: String
    ) throws -> Int32 {
        try openDirectory(
            components: absoluteComponents(for: url),
            operation: operation
        )
    }

    /// Opens an absolute directory one component at a time from `/`.
    /// `O_NOFOLLOW` is applied at every hop, not only to the final component.
    /// This prevents a replaced `Library` or `Caches` ancestor from redirecting
    /// a cleanup rule to another location.
    private static func openDirectory(
        components: [String],
        operation: String
    ) throws -> Int32 {
        var descriptor = open(
            "/",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw SecureTrashMoveError.posix(
                operation: operation,
                code: errno
            )
        }

        for component in components {
            let nextDescriptor = component.withCString { pointer in
                openat(
                    descriptor,
                    pointer,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard nextDescriptor >= 0 else {
                let errorCode = errno
                close(descriptor)
                throw SecureTrashMoveError.posix(
                    operation: operation,
                    code: errorCode
                )
            }
            close(descriptor)
            descriptor = nextDescriptor
        }
        return descriptor
    }

    private static func absoluteComponents(
        for url: URL
    ) throws -> [String] {
        guard url.isFileURL else {
            throw SecureTrashMoveError.invalidPath
        }

        var path = url.standardizedFileURL.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        let pathComponents = URL(
            fileURLWithPath: path,
            isDirectory: true
        ).pathComponents
        guard pathComponents.first == "/" else {
            throw SecureTrashMoveError.invalidPath
        }

        let relativeComponents = Array(pathComponents.dropFirst())
        guard relativeComponents.allSatisfy({
            !$0.isEmpty
                && $0 != "."
                && $0 != ".."
                && !$0.contains("/")
                && !$0.utf8.contains(0)
        }) else {
            throw SecureTrashMoveError.invalidPath
        }
        return relativeComponents
    }

    private static func openDirectory(
        named component: String,
        relativeTo parentFD: Int32
    ) throws -> Int32 {
        let descriptor = component.withCString { pointer in
            openat(
                parentFD,
                pointer,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw SecureTrashMoveError.posix(
                operation: "openat ancestor",
                code: errno
            )
        }
        return descriptor
    }

    private static func directoryIdentityMatches(
        _ url: URL,
        expectedStatus: stat
    ) throws -> Bool {
        let descriptor = try openDirectory(
            url,
            operation: "reopen Trash"
        )
        defer { close(descriptor) }

        var currentStatus = stat()
        guard fstat(descriptor, &currentStatus) == 0 else {
            throw SecureTrashMoveError.posix(
                operation: "fstat reopened Trash",
                code: errno
            )
        }
        return fileIdentifier(currentStatus)
            == fileIdentifier(expectedStatus)
            && volumeIdentifier(currentStatus)
                == volumeIdentifier(expectedStatus)
    }

    private static func verifyRestoredSource(
        named sourceName: String,
        in parentFD: Int32,
        parentURL: URL,
        expectedParentStatus: stat,
        fingerprint: FileFingerprint
    ) throws {
        guard try directoryIdentityMatches(
            parentURL,
            expectedStatus: expectedParentStatus
        ) else {
            throw SecureTrashMoveError.ancestorChanged
        }

        var restoredStatus = stat()
        let result = sourceName.withCString { sourcePointer in
            fstatat(
                parentFD,
                sourcePointer,
                &restoredStatus,
                AT_SYMLINK_NOFOLLOW
            )
        }
        guard result == 0 else {
            throw SecureTrashMoveError.posix(
                operation: "fstatat restored source",
                code: errno
            )
        }
        try validate(restoredStatus, against: fingerprint)
    }

    private static func posixCode(from error: Error) -> Int32? {
        guard let secureError = error as? SecureTrashMoveError,
              case let .posix(_, code) = secureError
        else {
            return nil
        }
        return code
    }

    private static func validate(
        _ status: stat,
        against fingerprint: FileFingerprint
    ) throws {
        guard isRegularFile(status), !fingerprint.isDirectory else {
            throw SecureTrashMoveError.unsupportedSource
        }
        guard fileIdentifier(status) == fingerprint.fileIdentifier,
              volumeIdentifier(status) == fingerprint.volumeIdentifier
        else {
            throw SecureTrashMoveError.sourceChanged
        }

        let metadata = metadata(from: status, isVolume: false)
        guard
            metadata.modifiedAt == fingerprint.modifiedAt,
            metadata.logicalSizeBytes == fingerprint.logicalSizeBytes,
            metadata.allocatedSizeBytes == fingerprint.allocatedSizeBytes
        else {
            throw SecureTrashMoveError.sourceChanged
        }
    }

    private static func metadata(
        from status: stat,
        isVolume: Bool
    ) -> CleanupFileMetadata {
        CleanupFileMetadata(
            isDirectory: isDirectory(status),
            isRegularFile: isRegularFile(status),
            isSymbolicLink: isSymbolicLink(status),
            isVolume: isVolume,
            modifiedAt: Date(
                timeIntervalSince1970:
                    Double(status.st_mtimespec.tv_sec)
                    + Double(status.st_mtimespec.tv_nsec) / 1_000_000_000
            ),
            fileIdentifier: fileIdentifier(status),
            volumeIdentifier: volumeIdentifier(status),
            logicalSizeBytes: nonnegative(status.st_size),
            allocatedSizeBytes: allocatedBytes(status)
        )
    }

    private static func fileIdentifier(_ status: stat) -> String {
        "\(status.st_dev):\(status.st_ino)"
    }

    private static func volumeIdentifier(_ status: stat) -> String {
        String(status.st_dev)
    }

    private static func isDirectory(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFDIR
    }

    private static func isRegularFile(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFREG
    }

    private static func isSymbolicLink(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFLNK
    }

    private static func nonnegative<T: BinaryInteger>(_ value: T) -> UInt64 {
        guard value > 0 else {
            return 0
        }
        return UInt64(clamping: value)
    }

    private static func allocatedBytes(_ status: stat) -> UInt64 {
        let blocks = nonnegative(status.st_blocks)
        let (bytes, overflow) = blocks.multipliedReportingOverflow(by: 512)
        return overflow ? UInt64.max : bytes
    }

    private static func renameExclusively(
        from sourceDirectoryFD: Int32,
        sourceName: String,
        to destinationDirectoryFD: Int32,
        destinationName: String
    ) -> Int32 {
        sourceName.withCString { sourcePointer in
            destinationName.withCString { destinationPointer in
                renameatx_np(
                    sourceDirectoryFD,
                    sourcePointer,
                    destinationDirectoryFD,
                    destinationPointer,
                    UInt32(RENAME_EXCL)
                )
            }
        }
    }

    private static func collisionSafeTrashName(
        for originalName: String
    ) -> String {
        let readableSuffix = String(originalName.unicodeScalars.prefix(40))
        return "\(UUID().uuidString)-\(readableSuffix)"
    }
}
