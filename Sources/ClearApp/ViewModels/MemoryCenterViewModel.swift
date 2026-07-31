import Combine
import ClearMac
import Foundation

@MainActor
final class MemoryCenterViewModel: ObservableObject {
    @Published private(set) var snapshot: MemorySnapshotViewData?
    @Published private(set) var applications: [RunningApplicationSnapshot] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionMessage: String?

    private let provider: any MemorySnapshotProviding
    private let applicationService: RunningApplicationService

    init(
        provider: any MemorySnapshotProviding,
        applicationService: RunningApplicationService =
            RunningApplicationService()
    ) {
        self.provider = provider
        self.applicationService = applicationService
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await provider.snapshot()
            applications = applicationService.snapshots()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestQuit(_ application: RunningApplicationSnapshot) async {
        actionMessage = nil

        switch applicationService.requestTermination(of: application.id) {
        case .requested:
            actionMessage = "已请求“\(application.name)”正常退出。"
            try? await Task.sleep(for: .seconds(1))
            applications = applicationService.snapshots()
        case .refused:
            actionMessage = "“\(application.name)”拒绝退出；Clear 不会自动强制结束它。"
        case .noLongerRunning:
            actionMessage = "“\(application.name)”已经退出。"
            applications = applicationService.snapshots()
        case .protectedApplication:
            actionMessage = "该应用受保护，Clear 不会请求退出。"
        }
    }
}
