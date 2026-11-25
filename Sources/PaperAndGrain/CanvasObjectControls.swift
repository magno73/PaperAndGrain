import SwiftUI

/// Positions an editable object in the artboard's top-left coordinate system.
struct CanvasObjectControl<Content: View>: View {
    let frame: CGRect
    let bounds: CGRect
    let selected: Bool
    let minimumSize: CGSize
    let accessibilityName: String
    var alignmentTargets: [CGRect] = []
    var allowsPhotoOverflow = false
    var preservesAspectRatio = false
    var showsWidthHandles = false
    var moveSpace: CoordinateSpace = .global
    var swapTargetAt: ((CGPoint) -> CanvasPhotoSwap.Target?)? = nil
    var onSwap: ((UUID) -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    let onSelect: () -> Void
    let onNudge: (CGSize) -> Bool
    let onChange: (CGRect) -> Void
    @ViewBuilder let content: (CGSize) -> Content

    @GestureState private var dragPreview: DragPreview?

    private struct DragPreview {
        let placement: CanvasAlignment.Result
        var swapTarget: CanvasPhotoSwap.Target? = nil
    }

    var body: some View {
        let visibleFrame = dragPreview?.placement.frame ?? frame
        let reachable = visibleFrame.intersection(bounds).offsetBy(dx: -visibleFrame.minX, dy: -visibleFrame.minY)
        content(visibleFrame.size)
            .frame(width: visibleFrame.width, height: visibleFrame.height)
            .clipped()
            .contentShape(ReachableFrame(rect: reachable))
            .gesture(drag())
            .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick?() })
            .focusable()
            // The app draws its own selection. The system focus ring stayed on the object
            // after a click on blank paper and looked like a selection that would not go away.
            .focusEffectDisabled()
            .onKeyPress(.space) {
                onSelect()
                return .handled
            }
            .canvasArrowKeys(perform: onNudge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onSelect)
            .overlay(alignment: .topLeading) {
                if selected, !reachable.isEmpty {
                    Rectangle()
                        .strokeBorder(.tint, lineWidth: 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .frame(width: reachable.width, height: reachable.height)
                        .overlay {
                            CanvasResizeHandles(size: reachable.size, showsWidthHandles: showsWidthHandles,
                                                widthGesture: { drag($0, widthOnly: true) }, gesture: { drag($0) })
                        }
                        .offset(x: reachable.minX, y: reachable.minY)
                }
            }
            .position(x: visibleFrame.midX, y: visibleFrame.midY)
            .preference(key: CanvasGuidePreference.self, value: dragPreview?.placement.guides ?? [])
            .preference(key: CanvasSwapTargetPreference.self, value: dragPreview?.swapTarget)
    }

    private func drag(_ corner: CanvasCorner? = nil, widthOnly: Bool = false) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: moveSpace)
            .updating($dragPreview) { value, preview, _ in
                preview = dragDestination(value, resizing: corner, widthOnly: widthOnly)
            }
            .onEnded { value in
                let destination = dragDestination(value, resizing: corner, widthOnly: widthOnly)
                if let target = destination.swapTarget, let onSwap {
                    onSwap(target.id)
                } else {
                    if !selected { onSelect() }
                    if destination.placement.frame != frame { onChange(destination.placement.frame) }
                }
            }
    }

    private func dragDestination(_ value: DragGesture.Value, resizing corner: CanvasCorner?,
                                 widthOnly: Bool) -> DragPreview {
        let targets = alignmentTargets.map { $0.intersection(bounds) }
        if let corner {
            return DragPreview(placement: corner.resizeDuringDrag(
                frame, by: widthOnly ? CGSize(width: value.translation.width, height: 0) : value.translation,
                in: bounds, minimumSize: minimumSize,
                preservesAspectRatio: preservesAspectRatio, allowsPhotoOverflow: allowsPhotoOverflow,
                alignmentTargets: preservesAspectRatio ? targets : [],
                snapsToEdges: preservesAspectRatio
            ))
        }
        let proposed = adjustedFrame(by: value.translation)
        if let target = swapTargetAt?(value.location) {
            return DragPreview(placement: CanvasAlignment.Result(frame: proposed, guides: []), swapTarget: target)
        }
        // The page edges are always magnetic, with a longer reach than other objects.
        return DragPreview(placement: CanvasAlignment.duringDrag(proposed, to: targets, edges: bounds, within: movementBounds))
    }

    private func adjustedFrame(by translation: CGSize) -> CGRect {
        CanvasPhotoGeometry.moved(frame, by: translation, within: movementBounds)
    }

    private var movementBounds: CGRect {
        allowsPhotoOverflow ? CanvasPhotoGeometry.movementBounds(for: frame.size, in: bounds) : bounds
    }

    private struct ReachableFrame: Shape {
        let rect: CGRect

        func path(in bounds: CGRect) -> Path {
            let intersection = rect.intersection(bounds)
            return intersection.isEmpty ? Path() : Path(intersection)
        }
    }
}

extension View {
    func canvasArrowKeys(perform action: @escaping (CGSize) -> Bool) -> some View {
        onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            guard press.modifiers.intersection([.command, .option, .control]).isEmpty else { return .ignored }
            let step: CGFloat = press.modifiers.contains(.shift) ? 10 : 1
            let offset: CGSize
            switch press.key {
            case .leftArrow: offset = CGSize(width: -step, height: 0)
            case .rightArrow: offset = CGSize(width: step, height: 0)
            case .upArrow: offset = CGSize(width: 0, height: -step)
            case .downArrow: offset = CGSize(width: 0, height: step)
            default: return .ignored
            }
            return action(offset) ? .handled : .ignored
        }
    }
}

struct CanvasSwapTargetPreference: PreferenceKey {
    static let defaultValue: CanvasPhotoSwap.Target? = nil

    static func reduce(value: inout CanvasPhotoSwap.Target?, nextValue: () -> CanvasPhotoSwap.Target?) {
        value = nextValue() ?? value
    }
}

enum CanvasPhotoGeometry {
    static func moved(_ frame: CGRect, by translation: CGSize, within limits: CGRect) -> CGRect {
        let x = min(limits.maxX - frame.width, max(limits.minX, frame.minX + translation.width))
        let y = min(limits.maxY - frame.height, max(limits.minY, frame.minY + translation.height))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    static func movementBounds(for size: CGSize, in bounds: CGRect) -> CGRect {
        let horizontalOverflow = max(0, size.width - bounds.width * PageRect.photoOverlapFraction)
        let verticalOverflow = max(0, size.height - bounds.height * PageRect.photoOverlapFraction)
        return bounds.insetBy(dx: -horizontalOverflow, dy: -verticalOverflow)
    }

    static func resizeLimits(current: CGFloat, minimum: CGFloat, anchor: CGFloat, trim: ClosedRange<CGFloat>,
                             towardStart: Bool) -> (minimum: CGFloat, maximum: CGFloat) {
        let length = trim.upperBound - trim.lowerBound
        let overlap = length * PageRect.photoOverlapFraction
        let distanceTowardHandle = towardStart ? anchor - trim.lowerBound : trim.upperBound - anchor
        let distanceBeyondAnchor = max(0, distanceTowardHandle - length)
        let lowerLimit = distanceBeyondAnchor > 0 ? distanceBeyondAnchor + overlap : minimum
        // A small frame close to an edge can grow until it still has a reachable part at that edge.
        let upperLimit = distanceTowardHandle < overlap ? distanceTowardHandle : length * PageRect.maximumPhotoScale
        return (min(current, max(minimum, lowerLimit)), max(current, upperLimit))
    }
}

enum CanvasCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    func resized(_ frame: CGRect, by translation: CGSize, in bounds: CGRect, minimumSize: CGSize,
                 preservesAspectRatio: Bool = false, allowsPhotoOverflow: Bool = false) -> CGRect {
        resizeResult(frame, by: translation, in: bounds, minimumSize: minimumSize,
                     preservesAspectRatio: preservesAspectRatio, allowsPhotoOverflow: allowsPhotoOverflow,
                     alignmentTargets: []).frame
    }

    func resizeResult(_ frame: CGRect, by translation: CGSize, in bounds: CGRect, minimumSize: CGSize,
                      preservesAspectRatio: Bool = false, allowsPhotoOverflow: Bool = false,
                      alignmentTargets: [CGRect], edges: CGRect? = nil, tolerance: CGFloat = 6) -> CanvasAlignment.Result {
        let anchor = CGPoint(x: isLeft ? frame.maxX : frame.minX, y: isTop ? frame.maxY : frame.minY)
        let horizontalSign: CGFloat = isLeft ? -1 : 1
        let verticalSign: CGFloat = isTop ? -1 : 1
        let width = frame.width + horizontalSign * translation.width
        let height = frame.height + verticalSign * translation.height
        let widthLimits = allowsPhotoOverflow
            ? CanvasPhotoGeometry.resizeLimits(current: frame.width, minimum: minimumSize.width, anchor: anchor.x,
                                               trim: bounds.minX...bounds.maxX, towardStart: isLeft)
            : (min(frame.width, minimumSize.width), isLeft ? anchor.x - bounds.minX : bounds.maxX - anchor.x)
        let heightLimits = allowsPhotoOverflow
            ? CanvasPhotoGeometry.resizeLimits(current: frame.height, minimum: minimumSize.height, anchor: anchor.y,
                                               trim: bounds.minY...bounds.maxY, towardStart: isTop)
            : (min(frame.height, minimumSize.height), isTop ? anchor.y - bounds.minY : bounds.maxY - anchor.y)

        let proportional = preservesAspectRatio && frame.width > 0 && frame.height > 0
        let proposed: CGSize
        if proportional {
            // Project the pointer onto the original diagonal while keeping its opposite corner fixed.
            let scale = (width * frame.width + height * frame.height) /
                (frame.width * frame.width + frame.height * frame.height)
            proposed = CGSize(width: frame.width * scale, height: frame.height * scale)
        } else {
            proposed = CGSize(width: width, height: height)
        }

        return CanvasAlignment.snapResize(proposed, anchoredAt: anchor, moving: self,
                                          aspectRatio: proportional ? frame.width / frame.height : nil,
                                          to: alignmentTargets, edges: edges, tolerance: tolerance) { request in
            let size: CGSize
            if proportional {
                let minScale = max(widthLimits.0 / frame.width, heightLimits.0 / frame.height)
                let maxScale = min(widthLimits.1 / frame.width, heightLimits.1 / frame.height)
                let scale = min(maxScale, max(minScale, request.width / frame.width))
                size = CGSize(width: frame.width * scale, height: frame.height * scale)
            } else {
                size = CGSize(width: min(widthLimits.1, max(widthLimits.0, request.width)),
                              height: min(heightLimits.1, max(heightLimits.0, request.height)))
            }
            return CGRect(x: isLeft ? anchor.x - size.width : anchor.x, y: isTop ? anchor.y - size.height : anchor.y,
                          width: size.width, height: size.height)
        }
    }
}

struct CanvasResizeHandles<ResizeGesture: Gesture>: View {
    let size: CGSize
    var showsWidthHandles = false
    var widthGesture: ((CanvasCorner) -> ResizeGesture)? = nil
    let gesture: (CanvasCorner) -> ResizeGesture

    var body: some View {
        ZStack {
            ForEach(CanvasCorner.allCases, id: \.self) { corner in
                handle(corner)
            }
            if showsWidthHandles, size.height >= 20, let widthGesture {
                widthHandle(.bottomLeft, with: widthGesture)
                widthHandle(.bottomRight, with: widthGesture)
            }
        }
    }

    private func widthHandle(_ side: CanvasCorner, with widthGesture: (CanvasCorner) -> ResizeGesture) -> some View {
        Capsule().fill(.tint)
            .strokeBorder(.white, lineWidth: 1)
            .frame(width: 6, height: 13)
            .frame(width: 13, height: 18)
            .contentShape(Rectangle())
            .gesture(widthGesture(side))
            .accessibilityHidden(true)
            .position(x: side.isLeft ? 6.5 : size.width - 6.5, y: size.height / 2)
    }

    private func handle(_ corner: CanvasCorner) -> some View {
        // Leave a clear drag surface at the center, also for small objects at low zoom.
        let width = min(20, size.width / 3)
        let height = min(20, size.height / 3)
        let markerSize = min(9, width, height)
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(.tint)
            .strokeBorder(.white, lineWidth: 1)
            .frame(width: markerSize, height: markerSize)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(gesture(corner))
            .accessibilityHidden(true)
            .position(x: corner.isLeft ? width / 2 : size.width - width / 2,
                      y: corner.isTop ? height / 2 : size.height - height / 2)
    }
}
