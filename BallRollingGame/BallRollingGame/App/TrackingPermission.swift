import AppTrackingTransparency
import UIKit

enum TrackingPermission {
    private static var hasRequestedThisLaunch = false

    /// Shows Apple's ATT dialog once while status is `.notDetermined`.
    /// Call only when the app is active and the first screen is visible.
    static func requestIfNeeded() {
        guard !hasRequestedThisLaunch else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        guard UIApplication.shared.applicationState == .active else { return }

        hasRequestedThisLaunch = true

        // Short delay so the main UI is on-screen first (Apple guidance).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}
