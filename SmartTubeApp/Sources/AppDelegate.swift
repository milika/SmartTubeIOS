#if os(iOS)
import UIKit
import OSLog
import SmartTubeIOS

private let appDelegateLog = Logger(subsystem: "com.void.smarttube.app", category: "AppDelegate")

/// Provides the per-screen orientation mask that UIKit queries on every
/// orientation-change event. Returns `.allButUpsideDown` so that
/// `UIWindowScene.requestGeometryUpdate` can successfully request landscape
/// when the player opens and portrait when it closes. Proactive
/// portrait↔landscape transitions are managed by `OrientationManager`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Return .allButUpsideDown at all times so that:
        // 1. UIKit's intersection with the view controller hierarchy does not
        //    restrict to portrait-only while the full-screen player cover is
        //    being presented (PresentationHostingController caches the supported
        //    mask at creation time, before PlayerView.onAppear fires).
        // 2. OrientationManager.requestGeometryUpdate can successfully request
        //    landscape when the player opens and portrait when it closes.
        // Proactive portrait↔landscape transitions are still managed by
        // OrientationManager via UIWindowScene.requestGeometryUpdate.
        let mask = UIInterfaceOrientationMask.allButUpsideDown
        appDelegateLog.notice("[AppDelegate] supportedInterfaceOrientationsFor — returning mask=\(mask.rawValue) playerIsActive=\(OrientationManager.shared.playerIsActive)")
        return mask
    }
}

// MARK: - ExternalDisplaySceneDelegate

/// Delegate for the external-display scene declared in Info.plist under
/// `UIWindowSceneSessionRoleExternalDisplayNonInteractive`.
///
/// iOS creates this scene when a display is attached over HDMI / USB-C. Handing it to
/// `ExternalDisplayManager` lets the TOS player's web view move onto that screen, so
/// the video plays there at full resolution instead of being mirrored from the phone.
@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        appDelegateLog.notice("[ExternalDisplay] scene willConnect")
        ExternalDisplayManager.shared.sceneConnected(windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        appDelegateLog.notice("[ExternalDisplay] scene didDisconnect")
        ExternalDisplayManager.shared.sceneDisconnected(scene)
    }
}
#endif
