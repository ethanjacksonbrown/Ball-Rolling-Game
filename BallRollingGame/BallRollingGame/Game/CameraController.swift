import SceneKit

final class CameraController {
    let node: SCNNode

    /// Chase cam behind the ball (-Z), looking forward along travel (+Z).
    private let height: Float = 8.2
    private let backDistance: Float = 11.5
    private let lookAhead: Float = 13

    init() {
        node = SCNNode()
        node.name = "camera"
        let camera = SCNCamera()
        camera.fieldOfView = 56
        camera.zNear = 0.1
        camera.zFar = 280
        camera.wantsHDR = false
        camera.wantsExposureAdaptation = false
        node.camera = camera
    }

    func snap(to target: SCNVector3) {
        node.position = desiredPosition(for: target)
        aim(at: target)
    }

    func update(following target: SCNVector3, deltaTime: Float) {
        let desired = desiredPosition(for: target)
        let blend = min(1, deltaTime * 8)
        node.position = SCNVector3(
            node.position.x + (desired.x - node.position.x) * blend,
            node.position.y + (desired.y - node.position.y) * blend,
            node.position.z + (desired.z - node.position.z) * blend
        )
        aim(at: target)
    }

    private func desiredPosition(for target: SCNVector3) -> SCNVector3 {
        SCNVector3(
            target.x,
            target.y + height,
            target.z - backDistance
        )
    }

    private func aim(at target: SCNVector3) {
        // Look ahead down the track. Explicit world-up prevents upside-down / sky-only views.
        let focus = SCNVector3(target.x, target.y + 0.4, target.z + lookAhead)
        node.look(at: focus, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }
}
