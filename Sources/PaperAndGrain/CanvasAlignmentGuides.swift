import AppKit
import SwiftUI

extension CanvasAlignment {
    static func duringDrag(_ frame: CGRect, to targets: [CGRect], within bounds: CGRect) -> Result {
        if NSEvent.modifierFlags.contains(.option) {
            return Result(frame: frame, guides: [])
        }
        return snap(frame, to: targets, within: bounds)
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
            context.stroke(path, with: .color(Color(red: 0.81, green: 0.13, blue: 0.39)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
