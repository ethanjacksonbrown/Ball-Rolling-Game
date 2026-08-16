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
                    TrackingPermission.requestIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        TrackingPermission.requestIfNeeded()
                    }
                }
        }
    }
}
