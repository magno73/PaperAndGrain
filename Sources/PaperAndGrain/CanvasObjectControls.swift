import SwiftUI

/// Positions an editable object in the artboard's top-left coordinate system.
struct CanvasObjectControl<Content: View>: View {
    let frame: CGRect
    let bounds: CGRect
    let selected: Bool
    let minimumSize: CGSize
    let accessibilityName: String
    var alignmentTargets: [CGRect] = []
    var preservesAspectRatio = false
    var onDoubleClick: (() -> Void)? = nil
    let onSelect: () -> Void
    let onChange: (CGRect) -> Void
    @ViewBuilder let content: (CGSize) -> Content

    @GestureState private var dragPreview: CanvasAlignment.Result?

    var body: some View {
        let visibleFrame = dragPreview?.frame ?? frame
        content(visibleFrame.size)
            .frame(width: visibleFrame.width, height: visibleFrame.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(drag().exclusively(before: tap))
            .focusable()
            .onKeyPress(.space) {
                onSelect()
                return .handled
            }
            .onMoveCommand(perform: nudge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onSelect)
            .overlay {
                if selected {
                    Rectangle()
                        .strokeBorder(.tint, lineWidth: 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if selected {
                    CanvasResizeHandles(size: visibleFrame.size) { corner in
                        drag(corner)
                    }
                }
            }
            .position(x: visibleFrame.midX, y: visibleFrame.midY)
            .preference(key: CanvasGuidePreference.self, value: dragPreview?.guides ?? [])
    }

    private var tap: AnyGesture<Void> {
        let select = TapGesture().onEnded(onSelect)
        if let onDoubleClick {
            return AnyGesture(TapGesture(count: 2).onEnded(onDoubleClick)
                .exclusively(before: select).map { _ in () })
        }
        return AnyGesture(select)
    }

    private func drag(_ corner: CanvasCorner? = nil) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .updating($dragPreview) { value, preview, _ in
                preview = dragDestination(by: value.translation, resizing: corner)
            }
            .onEnded { value in
                if !selected { onSelect() }
                let destination = dragDestination(by: value.translation, resizing: corner).frame
                if destination != frame { onChange(destination) }
            }
    }

    private func dragDestination(by translation: CGSize, resizing corner: CanvasCorner?) -> CanvasAlignment.Result {
        let proposed = adjustedFrame(by: translation, resizing: corner)
        if corner != nil {
            return CanvasAlignment.Result(frame: proposed, guides: [])
        }
        return CanvasAlignment.duringDrag(proposed, to: alignmentTargets, within: bounds)
    }

    private func nudge(_ direction: MoveCommandDirection) {
        let offset: CGSize
        switch direction {
        case .left: offset = CGSize(width: -1, height: 0)
        case .right: offset = CGSize(width: 1, height: 0)
        case .up: offset = CGSize(width: 0, height: -1)
        case .down: offset = CGSize(width: 0, height: 1)
        @unknown default: return
        }
        if !selected { onSelect() }
        let destination = adjustedFrame(by: offset)
        if destination != frame { onChange(destination) }
    }

    private func adjustedFrame(by translation: CGSize, resizing corner: CanvasCorner? = nil) -> CGRect {
        if let corner {
            return corner.resized(frame, by: translation, in: bounds, minimumSize: minimumSize,
                                  preservesAspectRatio: preservesAspectRatio)
        }
        let x = min(bounds.maxX - frame.width, max(bounds.minX, frame.minX + translation.width))
        let y = min(bounds.maxY - frame.height, max(bounds.minY, frame.minY + translation.height))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }
}

enum CanvasCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    func resized(_ frame: CGRect, by translation: CGSize, in bounds: CGRect, minimumSize: CGSize,
                 preservesAspectRatio: Bool = false) -> CGRect {
        let anchor = CGPoint(x: isLeft ? frame.maxX : frame.minX, y: isTop ? frame.maxY : frame.minY)
        let horizontalSign: CGFloat = isLeft ? -1 : 1
        let verticalSign: CGFloat = isTop ? -1 : 1
        let width = frame.width + horizontalSign * translation.width
        let height = frame.height + verticalSign * translation.height
        let minWidth = min(minimumSize.width, frame.width)
        let minHeight = min(minimumSize.height, frame.height)
        let maxWidth = isLeft ? anchor.x - bounds.minX : bounds.maxX - anchor.x
        let maxHeight = isTop ? anchor.y - bounds.minY : bounds.maxY - anchor.y

        let size: CGSize
        if preservesAspectRatio, frame.width > 0, frame.height > 0 {
            // Project the pointer onto the original diagonal while keeping its opposite corner fixed.
            let scale = (width * frame.width + height * frame.height) /
                (frame.width * frame.width + frame.height * frame.height)
            let minScale = max(minWidth / frame.width, minHeight / frame.height)
            let maxScale = min(maxWidth / frame.width, maxHeight / frame.height)
            let boundedScale = min(maxScale, max(minScale, scale))
            size = CGSize(width: frame.width * boundedScale, height: frame.height * boundedScale)
        } else {
            size = CGSize(width: min(maxWidth, max(minWidth, width)), height: min(maxHeight, max(minHeight, height)))
        }
        return CGRect(x: isLeft ? anchor.x - size.width : anchor.x, y: isTop ? anchor.y - size.height : anchor.y,
                      width: size.width, height: size.height)
    }
}

struct CanvasResizeHandles<ResizeGesture: Gesture>: View {
    let size: CGSize
    let gesture: (CanvasCorner) -> ResizeGesture

    var body: some View {
        ZStack {
            ForEach(CanvasCorner.allCases, id: \.self) { corner in
                handle(corner)
            }
        }
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
