import AppKit
import SwiftUI

extension CanvasAlignment {
    static func duringDrag(_ frame: CGRect, to targets: [CGRect], edges: CGRect? = nil, within bounds: CGRect) -> Result {
        if NSEvent.modifierFlags.contains(.option) {
            return Result(frame: frame, guides: [])
        }
        return snap(frame, to: targets, edges: edges, within: bounds)
    }
}

extension CanvasCorner {
    func resizeDuringDrag(_ frame: CGRect, by translation: CGSize, in bounds: CGRect, minimumSize: CGSize,
                          preservesAspectRatio: Bool = false, allowsPhotoOverflow: Bool = false,
                          alignmentTargets: [CGRect], snapsToEdges: Bool = true) -> CanvasAlignment.Result {
        let free = NSEvent.modifierFlags.contains(.option)
        return resizeResult(frame, by: translation, in: bounds, minimumSize: minimumSize,
                            preservesAspectRatio: preservesAspectRatio, allowsPhotoOverflow: allowsPhotoOverflow,
                            alignmentTargets: free ? [] : alignmentTargets, edges: free || !snapsToEdges ? nil : bounds)
    }
}

struct CanvasGuidePreference: PreferenceKey {
    static let defaultValue: [CanvasAlignment.Guide] = []

    static func reduce(value: inout [CanvasAlignment.Guide], nextValue: () -> [CanvasAlignment.Guide]) {
        value.append(contentsOf: nextValue())
    }
}

struct CanvasAlignmentGuides: View {
    let guides: [CanvasAlignment.Guide]

    var body: some View {
        Canvas { context, _ in
            let path = Path { path in
                for guide in guides {
                    switch guide {
                    case let .vertical(x, span):
                        path.move(to: CGPoint(x: x, y: span.lowerBound - 4))
                        path.addLine(to: CGPoint(x: x, y: span.upperBound + 4))
                    case let .horizontal(y, span):
                        path.move(to: CGPoint(x: span.lowerBound - 4, y: y))
                        path.addLine(to: CGPoint(x: span.upperBound + 4, y: y))
                    }
                }
            }
            context.stroke(path, with: .color(.white.opacity(0.86)), lineWidth: 3)
            context.stroke(path, with: .color(Theme.guide), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
