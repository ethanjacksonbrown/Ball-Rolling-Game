import SwiftUI
import SceneKit

struct SceneKitGameView: UIViewRepresentable {
    let game: GameSceneController

    func makeUIView(context: Context) -> SCNView {
        game.scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
