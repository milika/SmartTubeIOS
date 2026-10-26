import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@MainActor
@Suite("iOS player preference")
struct IOSPlayerPreferenceTests {
    @Test("YouTube player remains the default")
    func youtubePlayerIsDefault() {
        let store = SettingsStore(settings: AppSettings())

        #expect(store.useTOSPlayerOnIOS)
    }

    @Test("Native preference routes away from the YouTube player")
    func nativePreferenceDisablesTOSRouting() {
        var settings = AppSettings()
        settings.iosPlayerMode = .native
        let store = SettingsStore(settings: settings)

        #expect(!store.useTOSPlayerOnIOS)
    }

    @Test("UI-test override takes precedence over the persisted preference")
    func processOverrideTakesPrecedence() {
        var settings = AppSettings()
        settings.iosPlayerMode = .native
        let store = SettingsStore(settings: settings)

        store.useTOSPlayerOnIOS = true

        #expect(store.useTOSPlayerOnIOS)
        #expect(store.settings.iosPlayerMode == .native)
    }
}
