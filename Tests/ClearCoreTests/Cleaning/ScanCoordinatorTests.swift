import Foundation
import XCTest

@testable import ClearCore

final class ScanCoordinatorTests: XCTestCase {
    func testScanProducesCandidateWithFrozenFingerprint() async throws {
        let root = URL(fileURLWithPath: "/tmp/clear-test/cache", isDirectory: true)
        let child = root.appendingPathComponent("old.data")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [
                root: .directory(id: "root", modifiedAt: now),
                child: .file(
                    id: "child",
                    modifiedAt: now.addingTimeInterval(-10_000),
                    logical: 100,
                    allocated: 128
                )
            ],
            children: [root: [child]]
        )
        let scanner = ScanCoordinator(fileSystem: fileSystem)
        let rule = makeRule(root: root, minimumAge: 1_000)

        let result = try await scanner.scan(rules: [rule], now: now)

        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.issues.count, 0)
        XCTAssertEqual(result.candidates[0].url, child)
        XCTAssertEqual(
            result.candidates[0].fingerprint.allocatedSizeBytes,
            128
        )
        XCTAssertEqual(
            result.candidates[0].fingerprint.fileIdentifier,
            "child"
        )
    }

    func testScanSkipsYoungAndSymbolicLinkItems() async throws {
        let root = URL(fileURLWithPath: "/tmp/clear-test/cache", isDirectory: true)
        let young = root.appendingPathComponent("young")
        let link = root.appendingPathComponent("link")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [
                root: .directory(id: "root", modifiedAt: now),
                young: .file(
                    id: "young",
                    modifiedAt: now.addingTimeInterval(-10),
                    logical: 10,
                    allocated: 16
                ),
                link: .symbolicLink(id: "link", modifiedAt: now)
            ],
            children: [root: [young, link]]
        )
        let scanner = ScanCoordinator(fileSystem: fileSystem)

        let result = try await scanner.scan(
            rules: [makeRule(root: root, minimumAge: 1_000)],
            now: now
        )

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testScanRejectsDirectoryThatExceedsEntryLimit() async throws {
        let root = URL(fileURLWithPath: "/tmp/clear-test/cache", isDirectory: true)
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        let first = folder.appendingPathComponent("one")
        let second = folder.appendingPathComponent("two")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let old = now.addingTimeInterval(-10_000)
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [
                root: .directory(id: "root", modifiedAt: now),
                folder: .directory(id: "folder", modifiedAt: old),
                first: .file(
                    id: "one",
                    modifiedAt: old,
                    logical: 10,
                    allocated: 16
                ),
                second: .file(
                    id: "two",
                    modifiedAt: old,
                    logical: 10,
                    allocated: 16
                )
            ],
            children: [
                root: [folder],
                folder: [first, second]
            ]
        )
        let scanner = ScanCoordinator(fileSystem: fileSystem)
        let rule = CleanRule(
            id: "test",
            category: .applicationCache,
            rootURL: root,
            displayName: "Test",
            explanation: "Test",
            minimumAge: 1_000,
            maximumDepth: 4,
            maximumEntryCount: 2,
            risk: .attention
        )

        let result = try await scanner.scan(rules: [rule], now: now)

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.issues.map(\.kind), [.entryLimitExceeded])
    }

    func testScanNeverReturnsDirectoryAndKeepsYoungDescendant() async throws {
        let root = URL(fileURLWithPath: "/tmp/clear-test/cache", isDirectory: true)
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        let oldFile = folder.appendingPathComponent("old.bin")
        let youngFile = folder.appendingPathComponent("young.bin")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [
                root: .directory(id: "root", modifiedAt: now),
                folder: .directory(
                    id: "folder",
                    modifiedAt: now.addingTimeInterval(-20_000)
                ),
                oldFile: .file(
                    id: "old",
                    modifiedAt: now.addingTimeInterval(-10_000),
                    logical: 10,
                    allocated: 16
                ),
                youngFile: .file(
                    id: "young",
                    modifiedAt: now.addingTimeInterval(-10),
                    logical: 10,
                    allocated: 16
                )
            ],
            children: [
                root: [folder],
                folder: [oldFile, youngFile]
            ]
        )
        let scanner = ScanCoordinator(fileSystem: fileSystem)

        let result = try await scanner.scan(
            rules: [makeRule(root: root, minimumAge: 1_000)],
            now: now
        )

        XCTAssertEqual(result.candidates.map(\.url), [oldFile])
        XCTAssertTrue(
            result.candidates.allSatisfy {
                !$0.fingerprint.isDirectory
            }
        )
    }

    func testScanDiscardsCandidatesWhenRootDisappearsBeforeCommit()
        async throws
    {
        let root = URL(
            fileURLWithPath: "/tmp/clear-test/cache",
            isDirectory: true
        )
        let child = root.appendingPathComponent("old.data")
        let now = Date(timeIntervalSince1970: 2_000_000)
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [
                root: .directory(id: "root", modifiedAt: now),
                child: .file(
                    id: "child",
                    modifiedAt: now.addingTimeInterval(-10_000),
                    logical: 10,
                    allocated: 16
                )
            ],
            children: [root: [child]],
            removeMetadataAfterRead: [child: [root]]
        )
        let scanner = ScanCoordinator(fileSystem: fileSystem)

        let result = try await scanner.scan(
            rules: [makeRule(root: root, minimumAge: 1_000)],
            now: now
        )

        XCTAssertTrue(result.candidates.isEmpty)
    }

    private func makeRule(
        root: URL,
        minimumAge: TimeInterval
    ) -> CleanRule {
        CleanRule(
            id: "test",
            category: .applicationCache,
            rootURL: root,
            displayName: "Test",
            explanation: "Test cache",
            minimumAge: minimumAge,
            risk: .attention
        )
    }
}

actor InMemoryCleanupFileSystem: CleanupFileSystem {
    private var metadataByURL: [URL: CleanupFileMetadata]
    private var childrenByURL: [URL: [URL]]
    private var secureMoveErrors: [URL: SecureTrashMoveError]
    private var removeMetadataAfterRead: [URL: [URL]]
    private(set) var trashedURLs: [URL] = []

    init(
        metadata: [URL: CleanupFileMetadata],
        children: [URL: [URL]],
        secureMoveErrors: [URL: SecureTrashMoveError] = [:],
        removeMetadataAfterRead: [URL: [URL]] = [:]
    ) {
        metadataByURL = metadata
        childrenByURL = children
        self.secureMoveErrors = secureMoveErrors
        self.removeMetadataAfterRead = removeMetadataAfterRead
    }

    func metadata(at url: URL) async throws -> CleanupFileMetadata {
        guard let metadata = metadataByURL[url] else {
            throw CocoaError(.fileNoSuchFile)
        }
        if let urlsToRemove = removeMetadataAfterRead.removeValue(
            forKey: url
        ) {
            for urlToRemove in urlsToRemove {
                metadataByURL.removeValue(forKey: urlToRemove)
            }
        }
        return metadata
    }

    func children(
        of url: URL,
        limit: Int
    ) async throws -> CleanupDirectoryListing {
        let allEntries = childrenByURL[url] ?? []
        return CleanupDirectoryListing(
            entries: Array(allEntries.prefix(limit)),
            reachedLimit: allEntries.count > limit
        )
    }

    func securelyMoveToTrash(
        _ candidate: CleanCandidate
    ) async throws -> URL {
        if let error = secureMoveErrors[candidate.url] {
            throw error
        }
        guard metadataByURL[candidate.url] != nil else {
            throw CocoaError(.fileNoSuchFile)
        }
        trashedURLs.append(candidate.url)
        return URL(fileURLWithPath: "/tmp/trash")
            .appendingPathComponent(candidate.url.lastPathComponent)
    }

    func setMetadata(
        _ metadata: CleanupFileMetadata,
        for url: URL
    ) {
        metadataByURL[url] = metadata
    }
}

extension CleanupFileMetadata {
    static func directory(
        id: String,
        modifiedAt: Date,
        volumeID: String = "volume"
    ) -> CleanupFileMetadata {
        CleanupFileMetadata(
            isDirectory: true,
            isRegularFile: false,
            isSymbolicLink: false,
            isVolume: false,
            modifiedAt: modifiedAt,
            fileIdentifier: id,
            volumeIdentifier: volumeID,
            logicalSizeBytes: 0,
            allocatedSizeBytes: 0
        )
    }

    static func file(
        id: String,
        modifiedAt: Date,
        logical: UInt64,
        allocated: UInt64,
        volumeID: String = "volume"
    ) -> CleanupFileMetadata {
        CleanupFileMetadata(
            isDirectory: false,
            isRegularFile: true,
            isSymbolicLink: false,
            isVolume: false,
            modifiedAt: modifiedAt,
            fileIdentifier: id,
            volumeIdentifier: volumeID,
            logicalSizeBytes: logical,
            allocatedSizeBytes: allocated
        )
    }

    static func symbolicLink(
        id: String,
        modifiedAt: Date,
        volumeID: String = "volume"
    ) -> CleanupFileMetadata {
        CleanupFileMetadata(
            isDirectory: false,
            isRegularFile: false,
            isSymbolicLink: true,
            isVolume: false,
            modifiedAt: modifiedAt,
            fileIdentifier: id,
            volumeIdentifier: volumeID,
            logicalSizeBytes: 0,
            allocatedSizeBytes: 0
        )
    }
}
