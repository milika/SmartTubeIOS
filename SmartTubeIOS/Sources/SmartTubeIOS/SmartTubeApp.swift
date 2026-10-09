import SmartTubeIOSCore
import SwiftUI

/// App entry point – supports iOS 17+, iPadOS 17+, macOS 14+.
struct SmartTubeApp: App {
    @State private var api: InnerTubeAPI
    @State private var authService: AuthService
    @State private var browseViewModel: BrowseViewModel
    @State private var settingsStore: SettingsStore
    /// Shared download service used by video cards. Lives at the app scope so
    /// the download task is not orphaned when a card view leaves the hierarchy
    /// (e.g. after a context menu dismiss). PlayerView creates its own isolated
    /// service instance and is unaffected.
    #if ENABLE_DOWNLOADS
    @State private var cardDownloadService: VideoDownloadService
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let api = InnerTubeAPI()
        _api = State(initialValue: api)
        _authService = State(initialValue: AuthService())
        _browseViewModel = State(initialValue: BrowseViewModel(api: api))
        let settingsStore = SettingsStore()
        _settingsStore = State(initialValue: settingsStore)
        #if ENABLE_DOWNLOADS
        _cardDownloadService = State(initialValue: VideoDownloadService(api: api))
        #endif

        #if os(iOS)
        // #107: UIKit reads UIDesignRequiresCompatibility once at process launch to
        // decide whether to render iOS 26's Liquid Glass tab bar or the pre-26 style —
        // there's no live/runtime API to flip it, so this can only take effect on the
        // *next* launch after the user toggles it in Settings (see SettingsView's
        // "Restart the app for this to take effect" note next to the toggle).
        UserDefaults.standard.set(
            settingsStore.settings.disableLiquidGlass, forKey: "UIDesignRequiresCompatibility")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .environment(browseViewModel)
                .environment(settingsStore)
                .environment(\.innerTubeAPI, api)
                #if ENABLE_DOWNLOADS
                .environment(cardDownloadService)
                #endif
                #if ENABLE_DOWNLOADS
                .environment(DownloadStore.shared)
                #endif
                .onChange(of: authService.accessToken, initial: true) { _, newToken in
                    Task {
                        await api.setAuthToken(newToken)
                        await browseViewModel.updateAuthToken(newToken)
                    }
                }
                .onChange(of: settingsStore.settings.enabledSections) { _, newSections in
                    browseViewModel.configureSections(newSections)
                }
                .task {
                    // Sync enablement state on launch, then start the iCloud KV listener.
                    iCloudSyncManager.shared.syncEnabled = settingsStore.settings.iCloudSyncEnabled
                    await iCloudSyncManager.shared.start()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await authService.refreshIfNeeded()
                    authService.handleForeground()
                }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}
