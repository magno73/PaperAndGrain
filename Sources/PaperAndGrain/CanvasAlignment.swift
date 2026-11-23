import CoreGraphics

enum CanvasAlignment {
    struct Result {
        let frame: CGRect
        let guides: [Guide]
    }

    enum Guide: Equatable {
        case vertical(x: CGFloat, span: ClosedRange<CGFloat>)
        case horizontal(y: CGFloat, span: ClosedRange<CGFloat>)
    }

    /// Accepts the frame's free position in displayed points on every drag update.
    static func snap(_ frame: CGRect, to targets: [CGRect], within bounds: CGRect,
                     tolerance: CGFloat = 6) -> Result {
        guard !frame.isEmpty, !bounds.isEmpty, tolerance >= 0 else { return Result(frame: frame, guides: []) }

        let x = nearest(frame, to: targets, within: bounds, tolerance: tolerance, axis: (\.minX, \.midX, \.maxX))
        let y = nearest(frame, to: targets, within: bounds, tolerance: tolerance, axis: (\.minY, \.midY, \.maxY))
        let aligned = frame.offsetBy(dx: x?.offset ?? 0, dy: y?.offset ?? 0)

        var guides: [Guide] = []
        if let x {
            let span = min(aligned.minY, x.target.minY)...max(aligned.maxY, x.target.maxY)
            guides.append(.vertical(x: x.anchor, span: span))
        }
        if let y {
            let span = min(aligned.minX, y.target.minX)...max(aligned.maxX, y.target.maxX)
            guides.append(.horizontal(y: y.anchor, span: span))
        }
        return Result(frame: aligned, guides: guides)
    }

    private struct Match {
        let offset: CGFloat
        let anchor: CGFloat
        let target: CGRect
    }

    private typealias Axis = (start: KeyPath<CGRect, CGFloat>, center: KeyPath<CGRect, CGFloat>, end: KeyPath<CGRect, CGFloat>)

    private static func nearest(_ frame: CGRect, to targets: [CGRect], within bounds: CGRect,
                                tolerance: CGFloat, axis: Axis) -> Match? {
        let start = frame[keyPath: axis.start]
        let center = frame[keyPath: axis.center]
        let end = frame[keyPath: axis.end]
        let minimum = bounds[keyPath: axis.start] - start
        let maximum = bounds[keyPath: axis.end] - end

        var closest: Match?
        for target in targets where !target.isEmpty {
            let targetStart = target[keyPath: axis.start]
            let targetCenter = target[keyPath: axis.center]
            let targetEnd = target[keyPath: axis.end]
            let pairs = [(center, targetCenter), (start, targetStart), (end, targetEnd),
                         (start, targetEnd), (end, targetStart)]
            for (movingAnchor, targetAnchor) in pairs {
                let offset = targetAnchor - movingAnchor
                let distance = abs(offset)
                // Strict comparison keeps exact ties in target and pair order.
                if distance <= tolerance, offset >= minimum, offset <= maximum,
                   distance < abs(closest?.offset ?? .infinity) {
                    closest = Match(offset: offset, anchor: targetAnchor, target: target)
                }
            }
        }
        return closest
    }
}
