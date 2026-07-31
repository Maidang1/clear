import SwiftUI

@MainActor
struct ClearRootView: View {
    @State private var selection: SidebarDestination? = .memory

    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var historyStore: CleanupHistoryStore
    @StateObject private var memoryViewModel: MemoryCenterViewModel
    @StateObject private var cleanupViewModel: CleanupViewModel

    init() {
        let settingsStore = AppSettingsStore()
        let historyStore = CleanupHistoryStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _historyStore = StateObject(wrappedValue: historyStore)
        _memoryViewModel = StateObject(
            wrappedValue: MemoryCenterViewModel(
                provider: ClearMacMemorySnapshotProvider()
            )
        )
        _cleanupViewModel = StateObject(
            wrappedValue: CleanupViewModel(
                service: LocalCleanupService(),
                historyStore: historyStore
            )
        )
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $selection) {
                destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
                    .accessibilityLabel(destination.title)
            }
            .navigationTitle("Clear")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 860, minHeight: 600)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .memory {
        case .memory:
            MemoryCenterView(viewModel: memoryViewModel)
        case .cleanup:
            CleanupView(
                viewModel: cleanupViewModel,
                settingsStore: settingsStore
            )
        case .history:
            CleanupHistoryView(historyStore: historyStore)
        case .settings:
            SettingsView(settingsStore: settingsStore)
        }
    }
}
