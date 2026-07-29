import Darwin
import Foundation

public actor CleanupCoordinator {
    private let fileSystem: any CleanupFileSystem
    private let trustedRules: [RuleKey: CleanRule]

    public init() {
        self.fileSystem = LocalCleanupFileSystem()
        self.trustedRules = Self.index(DefaultCleanRules.make())
    }

    init(
        fileSystem: any CleanupFileSystem,
        trustedRules: [CleanRule]
    ) {
        self.fileSystem = fileSystem
        self.trustedRules = Self.index(trustedRules)
    }

    public func makePlan(
        candidates: [CleanCandidate],
        createdAt: Date = Date()
    ) -> CleanupPlan {
        var seen: Set<UUID> = []
        let uniqueCandidates = candidates.filter {
            seen.insert($0.id).inserted
        }
        return CleanupPlan(
            createdAt: createdAt,
            candidates: uniqueCandidates
        )
    }

    public func execute(
        _ plan: CleanupPlan,
        isApplicationRunning: @Sendable (String) async -> Bool,
        finishedAt: @Sendable () -> Date = Date.init
    ) async -> CleanupExecutionResult {
        var trashedItems: [TrashedItem] = []
        var uncertainMutations: [UncertainCleanupMutation] = []
        var failures: [CleanupItemFailure] = []

        for candidate in plan.candidates {
            if Task.isCancelled {
                failures.append(
                    failure(
                        candidate,
                        reason: .cancelled,
                        message: "操作已取消。"
                    )
                )
                continue
            }

            do {
                let trustedRule = try trustedRule(for: candidate)
                if trustedRule.requiresApplicationExit,
                   let bundleIdentifier =
                       trustedRule.relatedBundleIdentifier,
                   await isApplicationRunning(bundleIdentifier)
                {
                    throw CleanupBoundaryError(
                        reason: .applicationRunning,
                        message: "对应应用仍在运行，请退出后重新扫描。"
                    )
                }

                try Task.checkCancellation()
                let resultingURL = try await fileSystem
                    .securelyMoveToTrash(candidate)
                trashedItems.append(
                    TrashedItem(
                        candidateID: candidate.id,
                        originalURL: candidate.url,
                        resultingTrashURL: resultingURL,
                        estimatedAllocatedBytes:
                            candidate.fingerprint.allocatedSizeBytes
                    )
                )
            } catch SecureTrashMoveError.movedButUnverified(
                let details
            ) {
                uncertainMutations.append(
                    UncertainCleanupMutation(
                        candidateID: candidate.id,
                        originalURL: candidate.url,
                        lastKnownTrashURL: details.lastKnownTrashURL,
                        estimatedAllocatedBytes:
                            candidate.fingerprint.allocatedSizeBytes
                    )
                )
                failures.append(
                    failure(
                        candidate,
                        reason: .identityChanged,
                        message: "原路径已移动，但无法复验废纸篓中的最终状态；请检查废纸篓。"
                    )
                )
            } catch let boundary as CleanupBoundaryError {
                failures.append(
                    failure(
                        candidate,
                        reason: boundary.reason,
                        message: boundary.message
                    )
                )
            } catch {
                failures.append(
                    failure(
                        candidate,
                        reason: Self.failureReason(for: error),
                        message: Self.failureMessage(for: error)
                    )
                )
            }
        }

        return CleanupExecutionResult(
            planID: plan.id,
            finishedAt: finishedAt(),
            trashedItems: trashedItems,
            uncertainMutations: uncertainMutations,
            failures: failures
        )
    }

    private func trustedRule(
        for candidate: CleanCandidate
    ) throws -> CleanRule {
        let key = RuleKey(
            id: candidate.ruleID,
            version: candidate.ruleVersion
        )
        guard let rule = trustedRules[key],
              PathSafetyPolicy.isExactRoot(
                  candidate.allowedRootURL,
                  rule.rootURL
              ),
              candidate.category == rule.category,
              candidate.risk == rule.risk,
              candidate.relatedBundleIdentifier
                  == rule.relatedBundleIdentifier,
              candidate.requiresApplicationExit
                  == rule.requiresApplicationExit
        else {
            throw CleanupBoundaryError(
                reason: .ruleMismatch,
                message: "清理规则无法认证，请重新扫描。"
            )
        }
        guard PathSafetyPolicy.isStrictDescendant(
            candidate.url,
            of: rule.rootURL
        ) else {
            throw CleanupBoundaryError(
                reason: .outsideAllowedRoot,
                message: "项目不在规则允许的目录中。"
            )
        }
        guard !candidate.fingerprint.isDirectory else {
            throw CleanupBoundaryError(
                reason: .unsupportedItem,
                message: "首版只允许移动经过复验的普通文件。"
            )
        }
        return rule
    }

    private func failure(
        _ candidate: CleanCandidate,
        reason: CleanupFailureReason,
        message: String
    ) -> CleanupItemFailure {
        CleanupItemFailure(
            candidateID: candidate.id,
            displayName: candidate.displayName,
            reason: reason,
            message: message
        )
    }

    private static func index(
        _ rules: [CleanRule]
    ) -> [RuleKey: CleanRule] {
        Dictionary(
            uniqueKeysWithValues: rules.map {
                (
                    RuleKey(id: $0.id, version: $0.version),
                    $0
                )
            }
        )
    }

    private static func failureReason(for error: Error)
        -> CleanupFailureReason
    {
        if error is CancellationError {
            return .cancelled
        }
        guard let secureError = error as? SecureTrashMoveError else {
            let code = (error as NSError).code
            if code == Int(EACCES) || code == Int(EPERM) {
                return .permissionDenied
            }
            return .operationFailed
        }

        switch secureError {
        case .invalidPath:
            return .outsideAllowedRoot
        case .rootChanged, .ancestorChanged, .sourceChanged:
            return .identityChanged
        case .unsupportedSource:
            return .unsupportedItem
        case let .posix(_, code) where code == EACCES || code == EPERM:
            return .permissionDenied
        case let .posix(_, code) where code == ENOENT:
            return .noLongerExists
        case let .posix(_, code) where code == ELOOP || code == ENOTDIR:
            return .identityChanged
        case .trashUnavailable, .differentVolume,
             .movedButUnverified, .posix:
            return .operationFailed
        }
    }

    private static func failureMessage(for error: Error) -> String {
        guard let secureError = error as? SecureTrashMoveError else {
            return error.localizedDescription
        }

        switch secureError {
        case .invalidPath:
            return "路径不在可信规则范围内。"
        case .rootChanged:
            return "规则根目录自扫描后已被替换，请重新扫描。"
        case .ancestorChanged:
            return "项目的父目录自扫描后已变化，请重新扫描。"
        case .sourceChanged:
            return "文件自扫描后已变化，请重新扫描。"
        case .unsupportedSource:
            return "项目不再是受支持的普通文件。"
        case .trashUnavailable:
            return "无法安全打开当前用户的废纸篓。"
        case .differentVolume:
            return "项目与废纸篓不在同一文件系统，已拒绝操作。"
        case let .movedButUnverified(details):
            if let url = details.lastKnownTrashURL {
                return "原路径已移动但无法复验；最后已知废纸篓位置为 \(url.path)。"
            }
            return "原路径已移动但无法复验最终位置，请检查废纸篓。"
        case let .posix(operation, code):
            return "\(operation) 失败（错误码 \(code)）。"
        }
    }
}

private struct RuleKey: Hashable {
    let id: String
    let version: Int
}

private struct CleanupBoundaryError: Error {
    let reason: CleanupFailureReason
    let message: String
}
