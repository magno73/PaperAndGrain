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

    /// The page edges pull harder than other objects: a photo meant to reach the trim must not
    /// stop a few pixels short, or paper shows in print.
    static let edgeToleranceFactor: CGFloat = 1.5

    /// Every snapping reference with its own reach in displayed points.
    private static func references(_ targets: [CGRect], edges: CGRect?, tolerance: CGFloat) -> [(rect: CGRect, reach: CGFloat)] {
        targets.map { ($0, tolerance) } + (edges.map { [($0, tolerance * edgeToleranceFactor)] } ?? [])
    }

    /// Accepts the frame's free position in displayed points on every drag update.
    /// `edges` is the page or cover face: its edges and center snap with a longer reach.
    static func snap(_ frame: CGRect, to targets: [CGRect], edges: CGRect? = nil, within bounds: CGRect,
                     tolerance: CGFloat = 6) -> Result {
        guard !frame.isEmpty, !bounds.isEmpty, tolerance >= 0 else { return Result(frame: frame, guides: []) }
        let candidates = references(targets, edges: edges, tolerance: tolerance)
        let x = nearest(frame, to: candidates, within: bounds, axis: (\.minX, \.midX, \.maxX))
        let y = nearest(frame, to: candidates, within: bounds, axis: (\.minY, \.midY, \.maxY))
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

    /// `size` is the free resize proposal in displayed points, before snapping or clamping.
    static func snapResize(_ size: CGSize, anchoredAt anchor: CGPoint, moving corner: CanvasCorner,
                           aspectRatio: CGFloat?, to targets: [CGRect], edges: CGRect? = nil, tolerance: CGFloat,
                           constrainedFrame: (CGSize) -> CGRect) -> Result {
        let free = constrainedFrame(size)
        let candidates = references(targets, edges: edges, tolerance: tolerance)
        guard !candidates.isEmpty, tolerance >= 0 else { return Result(frame: free, guides: []) }

        let horizontal = resizeMatches(length: size.width, anchoredAt: anchor.x, towardStart: corner.isLeft,
                                       to: candidates, axis: (\.minX, \.midX, \.maxX))
        let vertical = resizeMatches(length: size.height, anchoredAt: anchor.y, towardStart: corner.isTop,
                                     to: candidates, axis: (\.minY, \.midY, \.maxY))

        let aligned: CGRect
        if let aspectRatio {
            var closest = CGFloat.infinity
            var best = free
            for match in horizontal {
                let candidate = constrainedFrame(CGSize(width: match.length, height: match.length / aspectRatio))
                let distance = abs(candidate.width - size.width)
                if match.aligns(in: candidate, along: \.width), distance < closest {
                    closest = distance
                    best = candidate
                }
            }
            for match in vertical {
                let candidate = constrainedFrame(CGSize(width: match.length * aspectRatio, height: match.length))
                let distance = abs(candidate.width - size.width)
                if match.aligns(in: candidate, along: \.height), distance < closest {
                    closest = distance
                    best = candidate
                }
            }
            aligned = best
        } else {
            let x = horizontal.first { match in
                match.aligns(in: constrainedFrame(CGSize(width: match.length, height: size.height)), along: \.width)
            }
            let y = vertical.first { match in
                match.aligns(in: constrainedFrame(CGSize(width: size.width, height: match.length)), along: \.height)
            }
            aligned = constrainedFrame(CGSize(width: x?.length ?? size.width, height: y?.length ?? size.height))
        }

        var guides: [Guide] = []
        if let x = horizontal.first(where: { $0.aligns(in: aligned, along: \.width) }) {
            let span = min(aligned.minY, x.target.minY)...max(aligned.maxY, x.target.maxY)
            guides.append(.vertical(x: x.anchor, span: span))
        }
        if let y = vertical.first(where: { $0.aligns(in: aligned, along: \.height) }) {
            let span = min(aligned.minX, y.target.minX)...max(aligned.maxX, y.target.maxX)
            guides.append(.horizontal(y: y.anchor, span: span))
        }
        return Result(frame: aligned, guides: guides)
    }

    private struct ResizeMatch {
        let length: CGFloat
        let anchor: CGFloat
        let target: CGRect
        let distance: CGFloat

        func aligns(in frame: CGRect, along dimension: KeyPath<CGRect, CGFloat>) -> Bool {
            abs(frame[keyPath: dimension] - length) < 0.000001
        }
    }

    private static func resizeMatches(length: CGFloat, anchoredAt anchor: CGFloat, towardStart: Bool,
                                      to targets: [(rect: CGRect, reach: CGFloat)], axis: Axis) -> [ResizeMatch] {
        guard length > 0 else { return [] }
        let direction: CGFloat = towardStart ? -1 : 1
        let matchingEdge = towardStart ? axis.start : axis.end
        let oppositeEdge = towardStart ? axis.end : axis.start
        let references: [(CGFloat, KeyPath<CGRect, CGFloat>)] = [(0.5, axis.center), (1, matchingEdge), (1, oppositeEdge)]
        var matches: [ResizeMatch] = []
        for (target, reach) in targets where !target.isEmpty {
            for (fraction, reference) in references {
                let position = target[keyPath: reference]
                let distance = abs(position - (anchor + direction * length * fraction))
                let alignedLength = (position - anchor) / (direction * fraction)
                if distance <= reach, alignedLength > 0 {
                    // Rank by how far inside its reach a match is, so the stronger page edge wins near the trim.
                    matches.append(ResizeMatch(length: alignedLength, anchor: position, target: target,
                                               distance: distance / max(0.0001, reach)))
                }
            }
        }
        return matches.sorted { $0.distance < $1.distance }
    }

    private struct Match {
        let offset: CGFloat
        let anchor: CGFloat
        let target: CGRect
    }

    private typealias Axis = (start: KeyPath<CGRect, CGFloat>, center: KeyPath<CGRect, CGFloat>, end: KeyPath<CGRect, CGFloat>)

    private static func nearest(_ frame: CGRect, to targets: [(rect: CGRect, reach: CGFloat)], within bounds: CGRect,
                                axis: Axis) -> Match? {
        let start = frame[keyPath: axis.start]
        let center = frame[keyPath: axis.center]
        let end = frame[keyPath: axis.end]
        let minimum = bounds[keyPath: axis.start] - start
        let maximum = bounds[keyPath: axis.end] - end

        var closest: Match?
        var closestScore = CGFloat.infinity
        for (target, reach) in targets where !target.isEmpty {
            let targetStart = target[keyPath: axis.start]
            let targetCenter = target[keyPath: axis.center]
            let targetEnd = target[keyPath: axis.end]
            let pairs = [(center, targetCenter), (start, targetStart), (end, targetEnd),
                         (start, targetEnd), (end, targetStart)]
            for (movingAnchor, targetAnchor) in pairs {
                let offset = targetAnchor - movingAnchor
                let distance = abs(offset)
                // Ranked by the share of each target's reach; strict comparison keeps exact ties in order.
                let score = distance / max(0.0001, reach)
                if distance <= reach, offset >= minimum, offset <= maximum, score < closestScore {
                    closest = Match(offset: offset, anchor: targetAnchor, target: target)
                    closestScore = score
                }
            }
        }
        return closest
    }
}
