import Foundation
import XCTest

@testable import ClearCore

final class LocalCleanupFileSystemTests: XCTestCase {
    func testScanRejectsSymbolicLinkRuleRoot() async throws {
        let fileManager = FileManager.default
        let fixtureRoot = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        )
            .appendingPathComponent(
                "clear-symlink-root-\(UUID().uuidString)",
                isDirectory: true
            )
        let actualRoot = fixtureRoot
            .appendingPathComponent("actual", isDirectory: true)
        let linkedRoot = fixtureRoot
            .appendingPathComponent("linked", isDirectory: true)

        try fileManager.createDirectory(
            at: actualRoot,
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(
            to: actualRoot.appendingPathComponent("old.log")
        )
        try fileManager.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: actualRoot
        )
        defer {
            try? fileManager.removeItem(at: fixtureRoot)
        }

        let fileSystem = LocalCleanupFileSystem()
        let rule = CleanRule(
            id: "symlink-root",
            category: .oldLog,
            rootURL: linkedRoot,
            displayName: "Symlink",
            explanation: "Fixture",
            minimumAge: 0,
            risk: .low
        )
        let scanner = ScanCoordinator(
            fileSystem: fileSystem,
            candidateLimit: 10
        )

        let result = try await scanner.scan(rules: [rule])

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.issues.map(\.kind), [.unsafePath])
    }

    func testAncestorSymbolicLinkCannotRedirectScanOrCleanup() async throws {
        let fileManager = FileManager.default
        let fixtureRoot = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        )
            .appendingPathComponent(
                "clear-ancestor-link-\(UUID().uuidString)",
                isDirectory: true
            )
        let fakeHome = fixtureRoot
            .appendingPathComponent("home", isDirectory: true)
        let library = fakeHome
            .appendingPathComponent("Library", isDirectory: true)
        let linkedCaches = library
            .appendingPathComponent("Caches", isDirectory: true)
        let outsideCaches = fixtureRoot
            .appendingPathComponent("outside", isDirectory: true)
        let actualRuleRoot = outsideCaches
            .appendingPathComponent("Browser", isDirectory: true)
        let linkedRuleRoot = linkedCaches
            .appendingPathComponent("Browser", isDirectory: true)
        let actualFile = actualRuleRoot.appendingPathComponent("old.data")
        let linkedFile = linkedRuleRoot.appendingPathComponent("old.data")
        let trashRoot = fixtureRoot
            .appendingPathComponent("trash", isDirectory: true)

        try fileManager.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: actualRuleRoot,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: trashRoot,
            withIntermediateDirectories: true
        )
        try Data("outside".utf8).write(to: actualFile)
        try fileManager.createSymbolicLink(
            at: linkedCaches,
            withDestinationURL: outsideCaches
        )
        defer {
            try? fileManager.removeItem(at: fixtureRoot)
        }

        let fileSystem = LocalCleanupFileSystem(
            trashDirectoryOverride: trashRoot
        )
        let rule = CleanRule(
            id: "ancestor-symlink",
            category: .applicationCache,
            rootURL: linkedRuleRoot,
            displayName: "Ancestor link",
            explanation: "Fixture",
            minimumAge: 0,
            risk: .attention
        )
        let scanner = ScanCoordinator(
            fileSystem: fileSystem,
            candidateLimit: 10
        )

        let scan = try await scanner.scan(rules: [rule])

        XCTAssertTrue(scan.candidates.isEmpty)
        XCTAssertEqual(scan.issues.map(\.kind), [.unsafePath])

        // Even a forged candidate carrying the outside target's exact
        // fingerprints must fail at the destructive boundary.
        let actualRootMetadata = try await fileSystem.metadata(
            at: actualRuleRoot
        )
        let actualFileMetadata = try await fileSystem.metadata(at: actualFile)
        let candidate = CleanCandidate(
            ruleID: rule.id,
            ruleVersion: rule.version,
            category: rule.category,
            risk: rule.risk,
            url: linkedFile,
            allowedRootURL: linkedRuleRoot,
            rootFingerprint: TrustedRootFingerprint(
                fileIdentifier: try XCTUnwrap(
                    actualRootMetadata.fileIdentifier
                ),
                volumeIdentifier: try XCTUnwrap(
                    actualRootMetadata.volumeIdentifier
                )
            ),
            displayName: linkedFile.lastPathComponent,
            explanation: rule.explanation,
            relatedBundleIdentifier: nil,
            requiresApplicationExit: false,
            fingerprint: FileFingerprint(
                fileIdentifier: try XCTUnwrap(
                    actualFileMetadata.fileIdentifier
                ),
                volumeIdentifier: try XCTUnwrap(
                    actualFileMetadata.volumeIdentifier
                ),
                modifiedAt: try XCTUnwrap(actualFileMetadata.modifiedAt),
                logicalSizeBytes: actualFileMetadata.logicalSizeBytes,
                allocatedSizeBytes:
                    actualFileMetadata.allocatedSizeBytes,
                isDirectory: false
            )
        )
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let plan = await coordinator.makePlan(candidates: [candidate])
        let cleanup = await coordinator.execute(
            plan,
            isApplicationRunning: { _ in false }
        )

        XCTAssertTrue(cleanup.trashedItems.isEmpty)
        XCTAssertEqual(cleanup.failures.count, 1)
        XCTAssertTrue(fileManager.fileExists(atPath: actualFile.path))
    }

    func testSecureMoveUsesTrustedRootAndMovesRegularFile() async throws {
        let fileManager = FileManager.default
        let fixtureRoot = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        )
            .appendingPathComponent(
                "clear-secure-trash-\(UUID().uuidString)",
                isDirectory: true
            )
        let ruleRoot = fixtureRoot
            .appendingPathComponent("cache", isDirectory: true)
        let trashRoot = fixtureRoot
            .appendingPathComponent("trash", isDirectory: true)
        let file = ruleRoot.appendingPathComponent("old.log")

        try fileManager.createDirectory(
            at: ruleRoot,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: trashRoot,
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: file)
        defer {
            try? fileManager.removeItem(at: fixtureRoot)
        }

        let fileSystem = LocalCleanupFileSystem(
            trashDirectoryOverride: trashRoot
        )
        let rule = CleanRule(
            id: "integration",
            category: .oldLog,
            rootURL: ruleRoot,
            displayName: "Integration",
            explanation: "Fixture",
            minimumAge: 0,
            risk: .low
        )
        let scanner = ScanCoordinator(
            fileSystem: fileSystem,
            candidateLimit: 10
        )
        let scan = try await scanner.scan(rules: [rule])
        let candidate = try XCTUnwrap(scan.candidates.first)
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let plan = await coordinator.makePlan(candidates: [candidate])

        let result = await coordinator.execute(
            plan,
            isApplicationRunning: { _ in false }
        )
        let trashContents = try fileManager.contentsOfDirectory(
            at: trashRoot,
            includingPropertiesForKeys: nil
        )

        XCTAssertEqual(result.trashedItems.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: file.path))
        XCTAssertEqual(trashContents.count, 1)
        XCTAssertEqual(
            try Data(contentsOf: trashContents[0]),
            Data("fixture".utf8)
        )
    }

    func testRenamedTrashDirectoryRollsSourceBack() async throws {
        let fileManager = FileManager.default
        let fixtureRoot = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        )
            .appendingPathComponent(
                "clear-trash-swap-\(UUID().uuidString)",
                isDirectory: true
            )
        let ruleRoot = fixtureRoot
            .appendingPathComponent("cache", isDirectory: true)
        let trashRoot = fixtureRoot
            .appendingPathComponent("trash", isDirectory: true)
        let holdingRoot = fixtureRoot
            .appendingPathComponent("holding", isDirectory: true)
        let file = ruleRoot.appendingPathComponent("old.log")

        try fileManager.createDirectory(
            at: ruleRoot,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: trashRoot,
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: file)
        defer {
            try? fileManager.removeItem(at: fixtureRoot)
        }

        let fileSystem = LocalCleanupFileSystem(
            trashDirectoryOverride: trashRoot,
            trashDirectoryOpenedHook: {
                try FileManager.default.moveItem(
                    at: trashRoot,
                    to: holdingRoot
                )
                try FileManager.default.createDirectory(
                    at: trashRoot,
                    withIntermediateDirectories: false
                )
            }
        )
        let rule = CleanRule(
            id: "trash-swap",
            category: .oldLog,
            rootURL: ruleRoot,
            displayName: "Trash swap",
            explanation: "Fixture",
            minimumAge: 0,
            risk: .low
        )
        let scanner = ScanCoordinator(
            fileSystem: fileSystem,
            candidateLimit: 10
        )
        let scan = try await scanner.scan(rules: [rule])
        let candidate = try XCTUnwrap(scan.candidates.first)
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let plan = await coordinator.makePlan(candidates: [candidate])

        let result = await coordinator.execute(
            plan,
            isApplicationRunning: { _ in false }
        )

        XCTAssertTrue(result.trashedItems.isEmpty)
        XCTAssertTrue(result.uncertainMutations.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(fileManager.fileExists(atPath: file.path))
        XCTAssertTrue(
            try fileManager.contentsOfDirectory(atPath: trashRoot.path)
                .isEmpty
        )
        XCTAssertTrue(
            try fileManager.contentsOfDirectory(atPath: holdingRoot.path)
                .isEmpty
        )
    }

    func testRenamedSourceParentIsRejectedBeforeMove() async throws {
        let fileManager = FileManager.default
        let fixtureRoot = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        )
            .appendingPathComponent(
                "clear-parent-swap-\(UUID().uuidString)",
                isDirectory: true
            )
        let ruleRoot = fixtureRoot
            .appendingPathComponent("cache", isDirectory: true)
        let sourceParent = ruleRoot
            .appendingPathComponent("nested", isDirectory: true)
        let movedParent = fixtureRoot
            .appendingPathComponent("holding", isDirectory: true)
        let trashRoot = fixtureRoot
            .appendingPathComponent("trash", isDirectory: true)
        let file = sourceParent.appendingPathComponent("old.log")
        let movedFile = movedParent.appendingPathComponent("old.log")

        try fileManager.createDirectory(
            at: sourceParent,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: trashRoot,
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: file)
        defer {
            try? fileManager.removeItem(at: fixtureRoot)
        }

        let fileSystem = LocalCleanupFileSystem(
            trashDirectoryOverride: trashRoot,
            trashDirectoryOpenedHook: {
                try FileManager.default.moveItem(
                    at: sourceParent,
                    to: movedParent
                )
            }
        )
        let rule = CleanRule(
            id: "parent-swap",
            category: .oldLog,
            rootURL: ruleRoot,
            displayName: "Parent swap",
            explanation: "Fixture",
            minimumAge: 0,
            risk: .low
        )
        let scanner = ScanCoordinator(
            fileSystem: fileSystem,
            candidateLimit: 10
        )
        let scan = try await scanner.scan(rules: [rule])
        let candidate = try XCTUnwrap(scan.candidates.first)
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let plan = await coordinator.makePlan(candidates: [candidate])

        let result = await coordinator.execute(
            plan,
            isApplicationRunning: { _ in false }
        )

        XCTAssertTrue(result.trashedItems.isEmpty)
        XCTAssertTrue(result.uncertainMutations.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: file.path))
        XCTAssertTrue(fileManager.fileExists(atPath: movedFile.path))
        XCTAssertTrue(
            try fileManager.contentsOfDirectory(atPath: trashRoot.path)
                .isEmpty
        )
    }
}
