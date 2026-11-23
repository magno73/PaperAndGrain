import SwiftUI

/// Edits a photo's crop aperture and the image behind it in artboard coordinates.
struct CanvasCropControl<Content: View>: View {
    let frame: CGRect
    let bounds: CGRect
    let sourceSize: CGSize
    let crop: PhotoCrop
    var minimumSize = CGSize(width: 16, height: 16)
    var allowsFrameResize = true
    var alignmentTargets: [CGRect] = []
    let onChange: (CGRect, PhotoCrop) -> Void
    @ViewBuilder let image: () -> Content

    @GestureState private var dragDraft: Draft?
    @GestureState private var magnifyDraft: Draft?

    var body: some View {
        let draft = magnifyDraft ?? dragDraft ?? current
        let aperture = draft.frame
        let extent = draft.crop.imageRect(for: sourceSize, in: aperture, fills: true)
        let reachable = aperture.intersection(bounds).offsetBy(dx: -aperture.minX, dy: -aperture.minY)
        ZStack(alignment: .topLeading) {
            image()
                .frame(width: extent.width, height: extent.height)
                .clipped()
                .mask {
                    ZStack(alignment: .topLeading) {
                        Color.white.opacity(0.3)
                        Rectangle()
                            .fill(.white)
                            .frame(width: aperture.width, height: aperture.height)
                            .position(x: aperture.midX - extent.minX, y: aperture.midY - extent.minY)
                    }
                }
                .position(x: extent.midX - bounds.minX, y: extent.midY - bounds.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Rectangle()
                .fill(.clear)
                .frame(width: aperture.width, height: aperture.height)
                .contentShape(CropHitArea(rect: reachable))
                .gesture(drag().exclusively(before: magnify))
                .overlay {
                    Rectangle().strokeBorder(.white, lineWidth: 1).allowsHitTesting(false)
                    Rectangle().inset(by: 1).strokeBorder(.tint, lineWidth: 1).allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if allowsFrameResize && !reachable.isEmpty {
                        CanvasResizeHandles(size: reachable.size) { corner in drag(corner) }
                            .frame(width: reachable.width, height: reachable.height)
                            .offset(x: reachable.minX, y: reachable.minY)
                    }
                }
                .position(x: aperture.midX - bounds.minX, y: aperture.midY - bounds.minY)
                .accessibilityHidden(true)
        }
        .frame(width: bounds.width, height: bounds.height)
        .clipped()
        .position(x: bounds.midX, y: bounds.midY)
        .preference(key: CanvasGuidePreference.self, value: draft.guides)
    }

    private var current: Draft { Draft(frame: frame, crop: crop) }

    private func drag(_ corner: CanvasCorner? = nil) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .updating($dragDraft) { value, draft, _ in
                draft = dragged(by: value.translation, corner: corner)
            }
            .onEnded { value in
                commit(dragged(by: value.translation, corner: corner))
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($magnifyDraft) { value, draft, _ in
                draft = magnified(by: value.magnification, around: value.startAnchor)
            }
            .onEnded { value in
                commit(magnified(by: value.magnification, around: value.startAnchor))
            }
    }

    private func dragged(by translation: CGSize, corner: CanvasCorner?) -> Draft {
        let extent = crop.imageRect(for: sourceSize, in: frame, fills: true)
        if let corner {
            let result = corner.resizeDuringDrag(frame, by: translation, in: bounds, minimumSize: minimumSize,
                                                 allowsPhotoOverflow: true,
                                                 alignmentTargets: alignmentTargets.map { $0.intersection(bounds) })
            return draft(for: extent, in: result.frame, guides: result.guides)
        }
        return draft(for: extent.offsetBy(dx: translation.width, dy: translation.height), in: frame)
    }

    private func magnified(by factor: CGFloat, around anchor: UnitPoint) -> Draft {
        let extent = crop.imageRect(for: sourceSize, in: frame, fills: true)
        let startingZoom = min(12, max(1, crop.zoom))
        let scale = min(12, max(1, startingZoom * factor)) / startingZoom
        let x = frame.minX + frame.width * anchor.x
        let y = frame.minY + frame.height * anchor.y
        let resized = CGRect(x: x + (extent.minX - x) * scale, y: y + (extent.minY - y) * scale,
                             width: extent.width * scale, height: extent.height * scale)
        return draft(for: resized, in: frame)
    }

    private func draft(for extent: CGRect, in aperture: CGRect, guides: [CanvasAlignment.Guide] = []) -> Draft {
        let base = PhotoCrop().imageRect(for: sourceSize, in: aperture, fills: true)
        guard base.width > 0, base.height > 0 else { return current }
        let zoom = min(12, max(1, extent.width / base.width))
        let extraWidth = base.width * zoom - aperture.width
        let extraHeight = base.height * zoom - aperture.height
        let x = extraWidth > 0.000001 ? min(1, max(0, (aperture.minX - extent.minX) / extraWidth)) : crop.x
        let y = extraHeight > 0.000001 ? min(1, max(0, (aperture.minY - extent.minY) / extraHeight)) : crop.y
        return Draft(frame: aperture, crop: PhotoCrop(x: x, y: y, zoom: zoom), guides: guides)
    }

    private func commit(_ draft: Draft) {
        let epsilon = 0.000001
        if draft.frame != frame || abs(draft.crop.x - crop.x) > epsilon || abs(draft.crop.y - crop.y) > epsilon
            || abs(draft.crop.zoom - crop.zoom) > epsilon {
            onChange(draft.frame, draft.crop)
        }
    }

    private struct Draft {
        let frame: CGRect
        let crop: PhotoCrop
        var guides: [CanvasAlignment.Guide] = []
    }

    private struct CropHitArea: Shape {
        let rect: CGRect

        func path(in bounds: CGRect) -> Path {
            let intersection = rect.intersection(bounds)
            return intersection.isEmpty ? Path() : Path(intersection)
        }
    }
}
