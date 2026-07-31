import Darwin
import Foundation
import XCTest

@testable import ClearCore

final class CleanupCoordinatorTests: XCTestCase {
    func testExecuteMovesUnchangedCandidateToTrash() async {
        let root = URL(fileURLWithPath: "/tmp/clear-test/cache", isDirectory: true)
        let file = root.appendingPathComponent("old.data")
        let modifiedAt = Date(timeIntervalSince1970: 1_000)
        let metadata = CleanupFileMetadata.file(
            id: "file",
            modifiedAt: modifiedAt,
            logical: 100,
            allocated: 128
        )
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [file: metadata],
            children: [:]
        )
        let rule = makeRule(root: root)
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let candidate = makeCandidate(
            root: root,
            file: file,
            metadata: metadata,
            rule: rule
        )
        let plan = await coordinator.makePlan(candidates: [candidate])

        let result = await coordinator.execute(
            plan,
            isApplicationRunning: { _ in false }
        )
        let trashedURLs = await fileSystem.trashedURLs

        XCTAssertEqual(result.trashedItems.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(trashedURLs, [file])
    }

    func testExecuteRejectsReplacedFile() async {
        let root = URL(fileURLWithPath: "/tmp/clear-test/cache", isDirectory: true)
        let file = root.appendingPathComponent("old.data")
        let modifiedAt = Date(timeIntervalSince1970: 1_000)
        let original = CleanupFileMetadata.file(
            id: "original",
            modifiedAt: modifiedAt,
            logical: 100,
            allocated: 128
        )
        let rule = makeRule(root: root)
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [file: original],
            children: [:],
            secureMoveErrors: [file: .sourceChanged]
        )
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let plan = await coordinator.makePlan(
            candidates: [
                makeCandidate(
                    root: root,
                    file: file,
                    metadata: original,
                    rule: rule
                )
            ]
        )

        let result = await coordinator.execute(
            plan,
            isApplicationRunning: { _ in false }
        )
        let trashedURLs = await fileSystem.trashedURLs

        XCTAssertTrue(result.trashedItems.isEmpty)
        XCTAssertEqual(result.failures.first?.reason, .identityChanged)
        XCTAssertEqual(trashedURLs, [])
    }

    func testUnverifiedMoveIsTrackedSeparatelyFromVerifiedTrash() async {
        let root = URL(
            fileURLWithPath: "/tmp/clear-test/cache",
            isDirectory: true
        )
        let file = root.appendingPathComponent("old.data")
        let expectedTrashURL = URL(
            fileURLWithPath: "/tmp/trash/old.data"
        )
        let metadata = CleanupFileMetadata.file(
            id: "file",
            modifiedAt: Date(timeIntervalSince1970: 1_000),
            logical: 100,
            allocated: 128
        )
        let rule = makeRule(root: root)
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [file: metadata],
            children: [:],
            secureMoveErrors: [
                file: .movedButUnverified(
                    UnverifiedMoveDetails(
                        lastKnownTrashURL: expectedTrashURL,
                        verificationErrorCode: ENOENT,
                        restorationErrorCode: nil
                    )
                )
            ]
        )
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let plan = await coordinator.makePlan(
            candidates: [
                makeCandidate(
                    root: root,
                    file: file,
                    metadata: metadata,
                    rule: rule
                )
            ]
        )

        let result = await coordinator.execute(
            plan,
            isApplicationRunning: { _ in false }
        )

        XCTAssertTrue(result.trashedItems.isEmpty)
        XCTAssertEqual(result.estimatedMovedBytes, 0)
        XCTAssertEqual(result.uncertainMutations.count, 1)
        XCTAssertEqual(
            result.uncertainMutations.first?.lastKnownTrashURL,
            expectedTrashURL
        )
        XCTAssertEqual(result.failures.first?.reason, .identityChanged)
    }

    func testExecuteRejectsPrefixConfusionOutsideAllowedRoot() async {
        let root = URL(fileURLWithPath: "/tmp/clear-test/cache", isDirectory: true)
        let file = URL(
            fileURLWithPath: "/tmp/clear-test/cache-evil/old.data"
        )
        let modifiedAt = Date(timeIntervalSince1970: 1_000)
        let metadata = CleanupFileMetadata.file(
            id: "file",
            modifiedAt: modifiedAt,
            logical: 100,
            allocated: 128
        )
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [file: metadata],
            children: [:]
        )
        let rule = makeRule(root: root)
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let plan = await coordinator.makePlan(
            candidates: [
                makeCandidate(
                    root: root,
                    file: file,
                    metadata: metadata,
                    rule: rule
                )
            ]
        )

        let result = await coordinator.execute(
            plan,
            isApplicationRunning: { _ in false }
        )
        let trashedURLs = await fileSystem.trashedURLs

        XCTAssertEqual(
            result.failures.first?.reason,
            .outsideAllowedRoot
        )
        XCTAssertEqual(trashedURLs, [])
    }

    func testExecuteRejectsCacheWhileRelatedApplicationIsRunning() async {
        let root = URL(fileURLWithPath: "/tmp/clear-test/cache", isDirectory: true)
        let file = root.appendingPathComponent("old.data")
        let metadata = CleanupFileMetadata.file(
            id: "file",
            modifiedAt: Date(timeIntervalSince1970: 1_000),
            logical: 100,
            allocated: 128
        )
        let rule = CleanRule(
            id: "test-running",
            category: .applicationCache,
            rootURL: root,
            displayName: "Test",
            explanation: "Test",
            minimumAge: 0,
            risk: .attention,
            relatedBundleIdentifier: "com.example.running",
            requiresApplicationExit: true
        )
        let fileSystem = InMemoryCleanupFileSystem(
            metadata: [file: metadata],
            children: [:]
        )
        let coordinator = CleanupCoordinator(
            fileSystem: fileSystem,
            trustedRules: [rule]
        )
        let candidate = CleanCandidate(
            ruleID: rule.id,
            ruleVersion: rule.version,
            category: rule.category,
            risk: rule.risk,
            url: file,
            allowedRootURL: root,
            rootFingerprint: TrustedRootFingerprint(
                fileIdentifier: "root",
                volumeIdentifier: "volume"
            ),
            displayName: file.lastPathComponent,
            explanation: rule.explanation,
            relatedBundleIdentifier: rule.relatedBundleIdentifier,
            requiresApplicationExit: true,
            fingerprint: FileFingerprint(
                fileIdentifier: metadata.fileIdentifier!,
                volumeIdentifier: metadata.volumeIdentifier!,
                modifiedAt: metadata.modifiedAt!,
                logicalSizeBytes: metadata.logicalSizeBytes,
                allocatedSizeBytes: metadata.allocatedSizeBytes,
                isDirectory: false
            )
        )
        let plan = await coordinator.makePlan(candidates: [candidate])

        let result = await coordinator.execute(
            plan,
            isApplicationRunning: {
                $0 == "com.example.running"
            }
        )
        let trashedURLs = await fileSystem.trashedURLs

        XCTAssertEqual(result.failures.first?.reason, .applicationRunning)
        XCTAssertTrue(result.trashedItems.isEmpty)
        XCTAssertEqual(trashedURLs, [])
    }

    private func makeCandidate(
        root: URL,
        file: URL,
        metadata: CleanupFileMetadata,
        rule: CleanRule
    ) -> CleanCandidate {
        CleanCandidate(
            ruleID: rule.id,
            ruleVersion: rule.version,
            category: .applicationCache,
            risk: .attention,
            url: file,
            allowedRootURL: root,
            rootFingerprint: TrustedRootFingerprint(
                fileIdentifier: "root",
                volumeIdentifier: "volume"
            ),
            displayName: file.lastPathComponent,
            explanation: "Test",
            relatedBundleIdentifier: nil,
            requiresApplicationExit: false,
            fingerprint: FileFingerprint(
                fileIdentifier: metadata.fileIdentifier!,
                volumeIdentifier: metadata.volumeIdentifier!,
                modifiedAt: metadata.modifiedAt!,
                logicalSizeBytes: metadata.logicalSizeBytes,
                allocatedSizeBytes: metadata.allocatedSizeBytes,
                isDirectory: metadata.isDirectory
            )
        )
    }

    private func makeRule(root: URL) -> CleanRule {
        CleanRule(
            id: "test",
            category: .applicationCache,
            rootURL: root,
            displayName: "Test",
            explanation: "Test",
            minimumAge: 0,
            risk: .attention
        )
    }
}
