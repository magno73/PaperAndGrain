import SwiftUI

/// Uses the backdrop and grip as drag surfaces underneath the independently editable text.
struct CanvasStoryGroup<Content: View>: View {
    let frame: CGRect
    let bounds: CGRect
    let backdrops: [CGRect]
    let alignmentTargets: [CGRect]
    let selected: Bool
    let moveLabel: String
    let onSelect: () -> Void
    let onMove: (CGSize) -> Void
    @ViewBuilder let content: () -> Content

    @GestureState private var dragPreview: CanvasAlignment.Result?

    var body: some View {
        let translation = dragPreview.map { offset(to: $0.frame) } ?? .zero
        ZStack(alignment: .topLeading) {
            if !backdrops.isEmpty {
                Color.clear
                    .contentShape(Path { $0.addRects(backdrops) })
                    .onTapGesture(perform: onSelect)
                    .gesture(drag)
                    .accessibilityHidden(true)
            }
            if selected {
                Rectangle().strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            content()
            grip
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .offset(translation)
        .preference(key: CanvasGuidePreference.self, value: dragPreview?.guides ?? [])
    }

    private var grip: some View {
        let availableRight = bounds.maxX - frame.maxX
        let x = availableRight >= 24 ? frame.maxX + 12 : min(bounds.maxX - 11, frame.maxX - 11)
        let y = frame.minY - bounds.minY >= 24 ? frame.minY - 12 : frame.minY + 11
        return Button(action: onSelect) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? .white : Color.accentColor)
                .frame(width: 22, height: 22)
                .background(selected ? Color.accentColor : .white.opacity(0.94), in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.35)) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(moveLabel)
        .accessibilityLabel(moveLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onMoveCommand { direction in
            let step: CGSize
            switch direction {
            case .left: step = CGSize(width: -1, height: 0)
            case .right: step = CGSize(width: 1, height: 0)
            case .up: step = CGSize(width: 0, height: -1)
            case .down: step = CGSize(width: 0, height: 1)
            @unknown default: return
            }
            onSelect()
            let delta = offset(to: movedFrame(by: step))
            if delta != .zero { onMove(delta) }
        }
        .gesture(drag)
        .position(x: max(bounds.minX + 11, x), y: min(bounds.maxY - 11, y))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .updating($dragPreview) { event, state, _ in
                state = destination(event.translation)
            }
            .onEnded { event in
                onSelect()
                let delta = offset(to: destination(event.translation).frame)
                if delta != .zero { onMove(delta) }
            }
    }

    private func destination(_ offset: CGSize) -> CanvasAlignment.Result {
        CanvasAlignment.duringDrag(movedFrame(by: offset), to: alignmentTargets, within: bounds)
    }

    private func movedFrame(by offset: CGSize) -> CGRect {
        frame.offsetBy(dx: min(bounds.maxX - frame.maxX, max(bounds.minX - frame.minX, offset.width)),
                       dy: min(bounds.maxY - frame.maxY, max(bounds.minY - frame.minY, offset.height)))
    }

    private func offset(to destination: CGRect) -> CGSize {
        CGSize(width: destination.minX - frame.minX, height: destination.minY - frame.minY)
    }
}
