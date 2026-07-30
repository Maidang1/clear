import AppKit
import Darwin
import Foundation

public struct RunningApplicationSnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let processIdentifier: pid_t
    public let bundleIdentifier: String?
    public let name: String
    public let isActive: Bool
    public let isHidden: Bool
    public let isProtected: Bool

    public init(
        id: String,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        name: String,
        isActive: Bool,
        isHidden: Bool,
        isProtected: Bool
    ) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.isActive = isActive
        self.isHidden = isHidden
        self.isProtected = isProtected
    }
}

public enum ApplicationTerminationResult: Equatable, Sendable {
    case requested
    case refused
    case noLongerRunning
    case protectedApplication
}

@MainActor
public final class RunningApplicationService {
    private static let protectedBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.loginwindow",
        "com.apple.SystemUIServer",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui"
    ]

    private var applicationsBySnapshotID: [String: NSRunningApplication] = [:]

    public init() {}

    public func snapshots() -> [RunningApplicationSnapshot] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var nextApplications: [String: NSRunningApplication] = [:]

        let snapshots: [RunningApplicationSnapshot] =
            NSWorkspace.shared.runningApplications.compactMap {
                application -> RunningApplicationSnapshot? in
            guard
                !application.isTerminated,
                application.activationPolicy == .regular,
                application.processIdentifier != currentPID
            else {
                return nil
            }

            let identifier = snapshotID(for: application)
            nextApplications[identifier] = application

            let bundleIdentifier = application.bundleIdentifier
            return RunningApplicationSnapshot(
                id: identifier,
                processIdentifier: application.processIdentifier,
                bundleIdentifier: bundleIdentifier,
                name: application.localizedName ?? bundleIdentifier ?? "PID \(application.processIdentifier)",
                isActive: application.isActive,
                isHidden: application.isHidden,
                isProtected: bundleIdentifier.map(Self.protectedBundleIdentifiers.contains) ?? true
            )
        }

        applicationsBySnapshotID = nextApplications

        return snapshots.sorted {
            if $0.isActive != $1.isActive {
                return $0.isActive
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }

    public func runningBundleIdentifiers() -> Set<String> {
        Set(
            NSWorkspace.shared.runningApplications.compactMap {
                application in
                guard !application.isTerminated else {
                    return nil
                }
                return application.bundleIdentifier
            }
        )
    }

    public func isApplicationFamilyRunning(
        bundleIdentifier: String
    ) -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            guard !application.isTerminated,
                  let runningIdentifier = application.bundleIdentifier
            else {
                return false
            }
            return runningIdentifier == bundleIdentifier
                || runningIdentifier.hasPrefix("\(bundleIdentifier).")
        }
    }

    public func requestTermination(of snapshotID: String) -> ApplicationTerminationResult {
        guard let application = applicationsBySnapshotID[snapshotID] else {
            return .noLongerRunning
        }
        guard !isProtected(application) else {
            return .protectedApplication
        }
        guard !application.isTerminated else {
            applicationsBySnapshotID.removeValue(forKey: snapshotID)
            return .noLongerRunning
        }

        return application.terminate() ? .requested : .refused
    }

    private func snapshotID(for application: NSRunningApplication) -> String {
        let launchTime = application.launchDate?.timeIntervalSince1970 ?? 0
        return "\(application.processIdentifier):\(launchTime)"
    }

    private func isProtected(_ application: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = application.bundleIdentifier else {
            return true
        }
        return Self.protectedBundleIdentifiers.contains(bundleIdentifier)
    }
}
