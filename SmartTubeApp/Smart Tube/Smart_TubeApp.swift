import FirebaseCore
import FirebaseCrashlytics
import SmartTubeIOS
import SmartTubeIOSCore
import SwiftUI

/// tvOS entry point for SmartTube.
/// The device-code + QR sign-in flow is natively designed for Apple TV —
/// the user reads a code on screen and activates on their phone at yt.be/activate.
@main
struct SmartTubeTVApp: App {
    // Declared without default values so that init() can call FirebaseApp.configure()
    // before any of these objects are instantiated.
    @State private var api: InnerTubeAPI
    @State private var authService: AuthService
    @State private var browseViewModel: BrowseViewModel
    @State private var settingsStore: SettingsStore
    /// Shared download service — required by RootView and VideoCardView even on
    /// tvOS (where downloads are disabled in UI). Must be present in the environment
    /// or SwiftUI throws a fatal "No Observable object of type VideoDownloadService"
    /// error at launch.
    #if ENABLE_DOWNLOADS
    @State private var cardDownloadService: VideoDownloadService
    #endif

    init() {
        // #92: see AppEntry.swift's init() for why order matters here — settingsStore
        // must exist before deciding whether to configure Firebase at all.
        let settingsStore = SettingsStore()
        CrashlyticsLogger.isEnabled = !settingsStore.settings.disableAnalytics
        if CrashlyticsLogger.isEnabled {
            FirebaseApp.configure()
        }
        let poTokenProvider: (any PoTokenProvider)? = {
            if let url = settingsStore.settings.poTokenServiceURL {
                return ServerPoTokenProvider(serviceURL: url)
            }
            return BotGuardClient()
        }()
        let api = InnerTubeAPI(authToken: nil, poTokenProvider: poTokenProvider)
        _api = State(initialValue: api)
        _authService = State(initialValue: AuthService())
        _browseViewModel = State(initialValue: BrowseViewModel(api: api))
        _settingsStore = State(initialValue: settingsStore)
        #if ENABLE_DOWNLOADS
        _cardDownloadService = State(initialValue: VideoDownloadService(api: api))
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
                .onChange(of: authService.accessToken, initial: true) { _, newToken in
                    Task {
                        await api.setAuthToken(newToken)
                        await browseViewModel.updateAuthToken(newToken)
                    }
                }
                .onChange(of: authService.sapisid, initial: true) { _, newSapisid in
                    Task { await api.setSAPISID(newSapisid) }
                }
                .onChange(of: settingsStore.settings.enabledSections) { _, newSections in
                    browseViewModel.configureSections(newSections)
                }
                .onChange(of: settingsStore.settings.historyState, initial: true) { _, newState in
                    browseViewModel.updateHistoryEnabled(newState == .enabled)
                }
        }
    }
}
