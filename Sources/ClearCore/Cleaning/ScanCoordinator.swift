import Darwin
import Foundation

public actor ScanCoordinator {
    private let fileSystem: any CleanupFileSystem
    private let candidateLimit: Int

    public init(candidateLimit: Int = 500) {
        self.fileSystem = LocalCleanupFileSystem()
        self.candidateLimit = max(1, candidateLimit)
    }

    init(
        fileSystem: any CleanupFileSystem,
        candidateLimit: Int = 500
    ) {
        self.fileSystem = fileSystem
        self.candidateLimit = max(1, candidateLimit)
    }

    public func scan(
        rules: [CleanRule],
        now: Date = Date()
    ) async throws -> CleanScanResult {
        var candidates: [CleanCandidate] = []
        var issues: [ScanIssue] = []
        var evaluatedRuleCount = 0

        for rule in rules {
            try Task.checkCancellation()
            guard candidates.count < candidateLimit else {
                break
            }
            evaluatedRuleCount += 1

            do {
                let rootMetadata = try await fileSystem.metadata(
                    at: rule.rootURL
                )
                guard
                    rootMetadata.isDirectory,
                    !rootMetadata.isSymbolicLink,
                    !rootMetadata.isVolume,
                    let rootFileIdentifier =
                        rootMetadata.fileIdentifier,
                    let rootVolumeIdentifier =
                        rootMetadata.volumeIdentifier
                else {
                    issues.append(
                        issue(
                            rule: rule,
                            path: rule.rootURL.path,
                            kind: .unsafePath,
                            message: "规则根目录不是安全的普通目录，已跳过。"
                        )
                    )
                    continue
                }

                let rootFingerprint = TrustedRootFingerprint(
                    fileIdentifier: rootFileIdentifier,
                    volumeIdentifier: rootVolumeIdentifier
                )
                let walkResult = try await walkDirectory(
                    rule.rootURL,
                    rule: rule,
                    rootFingerprint: rootFingerprint,
                    depth: 0,
                    remainingEntries: rule.maximumEntryCount,
                    remainingCandidates: candidateLimit - candidates.count,
                    now: now
                )

                let rootAfter = try await fileSystem.metadata(at: rule.rootURL)
                guard
                    rootAfter.fileIdentifier == rootFileIdentifier,
                    rootAfter.volumeIdentifier == rootVolumeIdentifier,
                    rootAfter.isDirectory,
                    !rootAfter.isSymbolicLink
                else {
                    issues.append(
                        issue(
                            rule: rule,
                            path: rule.rootURL.path,
                            kind: .changedDuringScan,
                            message: "规则根目录在扫描期间发生变化，本规则结果已丢弃。"
                        )
                    )
                    continue
                }
                candidates.append(contentsOf: walkResult.candidates)
                issues.append(contentsOf: walkResult.issues)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ScanFailure {
                issues.append(
                    issue(
                        rule: rule,
                        path: rule.rootURL.path,
                        kind: error.kind,
                        message: error.message
                    )
                )
            } catch {
                if Self.isMissingPath(error) {
                    // Built-in rules for applications that are not installed
                    // are expected to have no directory.
                    continue
                }
                issues.append(
                    issue(
                        rule: rule,
                        path: rule.rootURL.path,
                        kind: Self.issueKind(for: error),
                        message: error.localizedDescription
                    )
                )
            }
        }

        candidates.sort {
            if $0.fingerprint.allocatedSizeBytes
                == $1.fingerprint.allocatedSizeBytes
            {
                return $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
            return $0.fingerprint.allocatedSizeBytes
                > $1.fingerprint.allocatedSizeBytes
        }

        return CleanScanResult(
            scannedAt: now,
            candidates: candidates,
            issues: issues,
            evaluatedRuleCount: evaluatedRuleCount
        )
    }

    private func walkDirectory(
        _ directory: URL,
        rule: CleanRule,
        rootFingerprint: TrustedRootFingerprint,
        depth: Int,
        remainingEntries: Int,
        remainingCandidates: Int,
        now: Date
    ) async throws -> WalkResult {
        try Task.checkCancellation()
        guard depth <= rule.maximumDepth else {
            throw ScanFailure(
                kind: .entryLimitExceeded,
                message: "目录深度超出规则上限，已保守跳过。"
            )
        }
        guard remainingEntries > 0, remainingCandidates > 0 else {
            return WalkResult()
        }

        let listing = try await fileSystem.children(
            of: directory,
            limit: remainingEntries
        )
        guard !listing.reachedLimit else {
            throw ScanFailure(
                kind: .entryLimitExceeded,
                message: "目录项目过多，已保守跳过本规则。"
            )
        }

        var result = WalkResult()
        for child in listing.entries {
            try Task.checkCancellation()
            guard result.candidates.count < remainingCandidates else {
                break
            }
            result.visitedEntryCount += 1
            guard result.visitedEntryCount <= remainingEntries else {
                throw ScanFailure(
                    kind: .entryLimitExceeded,
                    message: "目录项目过多，已保守跳过本规则。"
                )
            }

            guard PathSafetyPolicy.isStrictDescendant(
                child,
                of: rule.rootURL
            ) else {
                result.issues.append(
                    issue(
                        rule: rule,
                        path: child.path,
                        kind: .unsafePath,
                        message: "项目超出规则允许范围，已跳过。"
                    )
                )
                continue
            }

            do {
                let metadata = try await fileSystem.metadata(at: child)
                guard
                    metadata.volumeIdentifier
                        == rootFingerprint.volumeIdentifier
                else {
                    result.issues.append(
                        issue(
                            rule: rule,
                            path: child.path,
                            kind: .unsafePath,
                            message: "项目跨越了规则所在卷，已跳过。"
                        )
                    )
                    continue
                }
                if metadata.isSymbolicLink || metadata.isVolume {
                    continue
                }

                if metadata.isDirectory {
                    let nestedBudget = max(
                        0,
                        remainingEntries - result.visitedEntryCount
                    )
                    let nested = try await walkDirectory(
                        child,
                        rule: rule,
                        rootFingerprint: rootFingerprint,
                        depth: depth + 1,
                        remainingEntries: nestedBudget,
                        remainingCandidates:
                            remainingCandidates - result.candidates.count,
                        now: now
                    )
                    result.candidates.append(contentsOf: nested.candidates)
                    result.issues.append(contentsOf: nested.issues)
                    result.visitedEntryCount += nested.visitedEntryCount
                    guard result.visitedEntryCount <= remainingEntries else {
                        throw ScanFailure(
                            kind: .entryLimitExceeded,
                            message: "目录项目过多，已保守跳过本规则。"
                        )
                    }
                    continue
                }

                guard metadata.isRegularFile,
                      let modifiedAt = metadata.modifiedAt,
                      now.timeIntervalSince(modifiedAt) >= rule.minimumAge,
                      metadata.allocatedSizeBytes > 0,
                      let fileIdentifier = metadata.fileIdentifier,
                      let volumeIdentifier = metadata.volumeIdentifier
                else {
                    continue
                }

                let metadataAfter = try await fileSystem.metadata(at: child)
                guard metadata == metadataAfter else {
                    result.issues.append(
                        issue(
                            rule: rule,
                            path: child.path,
                            kind: .changedDuringScan,
                            message: "文件在扫描期间发生变化，已跳过。"
                        )
                    )
                    continue
                }

                result.candidates.append(
                    CleanCandidate(
                        ruleID: rule.id,
                        ruleVersion: rule.version,
                        category: rule.category,
                        risk: rule.risk,
                        url: child,
                        allowedRootURL: rule.rootURL,
                        rootFingerprint: rootFingerprint,
                        displayName: child.lastPathComponent,
                        explanation: rule.explanation,
                        relatedBundleIdentifier:
                            rule.relatedBundleIdentifier,
                        requiresApplicationExit:
                            rule.requiresApplicationExit,
                        fingerprint: FileFingerprint(
                            fileIdentifier: fileIdentifier,
                            volumeIdentifier: volumeIdentifier,
                            modifiedAt: modifiedAt,
                            logicalSizeBytes: metadata.logicalSizeBytes,
                            allocatedSizeBytes:
                                metadata.allocatedSizeBytes,
                            isDirectory: false
                        )
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ScanFailure {
                // A traversal budget violation invalidates the whole rule.
                // Propagating it prevents sibling directories from repeatedly
                // consuming the same remaining-entry budget.
                throw error
            } catch {
                result.issues.append(
                    issue(
                        rule: rule,
                        path: child.path,
                        kind: Self.issueKind(for: error),
                        message: error.localizedDescription
                    )
                )
            }
        }
        return result
    }

    private func issue(
        rule: CleanRule,
        path: String,
        kind: ScanIssueKind,
        message: String
    ) -> ScanIssue {
        ScanIssue(
            ruleID: rule.id,
            path: path,
            kind: kind,
            message: message
        )
    }

    private static func issueKind(for error: Error) -> ScanIssueKind {
        if let secureError = error as? SecureTrashMoveError {
            switch secureError {
            case let .posix(_, code)
                where code == EACCES || code == EPERM:
                return .permissionDenied
            case .invalidPath, .rootChanged, .ancestorChanged,
                 .sourceChanged, .unsupportedSource:
                return .unsafePath
            case let .posix(_, code)
                where code == ELOOP || code == ENOTDIR:
                return .unsafePath
            case .trashUnavailable, .differentVolume,
                 .movedButUnverified, .posix:
                break
            }
        }

        let errorCode = (error as NSError).code
        if errorCode == Int(EACCES) || errorCode == Int(EPERM)
            || errorCode == NSFileReadNoPermissionError
        {
            return .permissionDenied
        }
        return .unreadableMetadata
    }

    private static func isMissingPath(_ error: Error) -> Bool {
        if let secureError = error as? SecureTrashMoveError,
           case let .posix(_, code) = secureError
        {
            return code == ENOENT
        }
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain
            && cocoaError.code == NSFileNoSuchFileError
    }
}

private struct WalkResult {
    var candidates: [CleanCandidate] = []
    var issues: [ScanIssue] = []
    var visitedEntryCount = 0
}

private struct ScanFailure: Error {
    let kind: ScanIssueKind
    let message: String
}
