import Combine
import Foundation

@MainActor
final class CleanupViewModel: ObservableObject {
    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published var selectedCandidateIDs: Set<UUID> = []
    @Published private(set) var permissionIssues: [PermissionIssue] = []
    @Published private(set) var failures: [CleanupFailure] = []
    @Published private(set) var lastScannedAt: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var hasCompletedFirstScan = false

    private let service: any CleanupServicing
    private let historyStore: CleanupHistoryStore

    init(
        service: any CleanupServicing,
        historyStore: CleanupHistoryStore
    ) {
        self.service = service
        self.historyStore = historyStore
    }

    var selectedCandidates: [CleanupCandidate] {
        candidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    var selectedBytes: UInt64 {
        selectedCandidates.reduce(0) {
            $0 + $1.estimatedAllocatedBytes
        }
    }

    var allCandidatesAreSelected: Bool {
        !candidates.isEmpty
            && selectedCandidateIDs.count == candidates.count
    }

    var canClean: Bool {
        !selectedCandidateIDs.isEmpty && !isScanning && !isCleaning
    }

    func scan(options: CleanupScanOptions) async {
        guard !isScanning && !isCleaning else { return }

        isScanning = true
        errorMessage = nil
        noticeMessage = nil
        failures = []
        defer {
            isScanning = false
            hasCompletedFirstScan = true
        }

        do {
            let result = try await service.scan(options: options)
            candidates = result.candidates
            permissionIssues = result.permissionIssues
            lastScannedAt = result.scannedAt
            selectedCandidateIDs = selectedCandidateIDs.intersection(
                Set(result.candidates.map(\.id))
            )
        } catch is CancellationError {
            return
        } catch {
            candidates = []
            permissionIssues = []
            selectedCandidateIDs = []
            errorMessage = error.localizedDescription
        }
    }

    func toggleSelection(for candidate: CleanupCandidate) {
        if selectedCandidateIDs.contains(candidate.id) {
            selectedCandidateIDs.remove(candidate.id)
        } else {
            selectedCandidateIDs.insert(candidate.id)
        }
    }

    func setCandidate(_ candidate: CleanupCandidate, selected: Bool) {
        if selected {
            selectedCandidateIDs.insert(candidate.id)
        } else {
            selectedCandidateIDs.remove(candidate.id)
        }
    }

    func toggleSelectAll() {
        if allCandidatesAreSelected {
            selectedCandidateIDs = []
        } else {
            selectedCandidateIDs = Set(candidates.map(\.id))
        }
    }

    func cleanSelectedItems() async {
        let selection = selectedCandidates
        guard !selection.isEmpty, !isCleaning, !isScanning else { return }

        isCleaning = true
        errorMessage = nil
        noticeMessage = nil
        failures = []
        defer { isCleaning = false }

        let result = await service.moveToTrash(selection)
        historyStore.record(result)
        failures = result.failures

        let movedIDs = Set(
            result.trashedItems.map(\.candidateID)
                + result.uncertainMutations.map(\.candidateID)
        )
        candidates.removeAll { movedIDs.contains($0.id) }
        selectedCandidateIDs.subtract(movedIDs)

        if !result.trashedItems.isEmpty {
            noticeMessage = [
                "已将 \(result.trashedItems.count) 个项目移入废纸篓",
                "约 \(result.estimatedMovedBytes.clearFormattedBytes)",
                "清空废纸篓后才会真正释放空间。"
            ].joined(separator: "，")
        }

        if !result.uncertainMutations.isEmpty {
            errorMessage = [
                "\(result.uncertainMutations.count) 个项目的移动结果无法确认。",
                "请检查废纸篓，然后重新扫描。"
            ].joined(separator: " ")
        } else if result.trashedItems.isEmpty, !result.failures.isEmpty {
            errorMessage = "没有项目被移动，请查看下方错误后重新扫描。"
        }
    }

    func dismissMessages() {
        errorMessage = nil
        noticeMessage = nil
        failures = []
    }
}
