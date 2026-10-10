import SwiftUI

@main
struct BallRollingGameApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .onAppear {
                    AdManager.shared.startIfNeeded()
                    TrackingPermission.requestIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        AdManager.shared.startIfNeeded()
                        TrackingPermission.requestIfNeeded()
                        GameMusic.shared.start()
                    case .inactive, .background:
                        GameMusic.shared.stop()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
