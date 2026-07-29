import UIKit

final class DragInputHandler {
    /// -1 ... 1, positive = screen-right = world +X
    private(set) var lateral: Float = 0
    private var isDragging = false

    func handlePan(translation: CGPoint, state: UIGestureRecognizer.State, viewSize: CGSize) {
        switch state {
        case .began:
            isDragging = true
            lateral = 0
        case .changed:
            guard isDragging else { return }
            let width = max(viewSize.width, 1)
            // Finger right → ball moves screen-right. Negated to match the chase-cam view.
            let nx = Float(translation.x / (width * 0.28))
            lateral = max(-1, min(1, -nx))
        case .ended, .cancelled, .failed:
            isDragging = false
            lateral = 0
        default:
            break
        }
    }

    func reset() {
        isDragging = false
        lateral = 0
    }
}
