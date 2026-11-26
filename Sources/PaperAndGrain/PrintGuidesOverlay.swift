import SwiftUI

/// The knife marks on the canvas: a dashed safe line inside each page and one thin bleed line around
/// the outside of the pages shown. It draws over the artboard without changing its size, ignores the
/// pointer and exists only on the editor canvas: thumbnails, Browse the Book and the PDF never draw it.
struct PrintGuidesOverlay: View {
    struct Page {
        /// Top left of the page's trim, in canvas points.
        let origin: CGPoint
        let guides: PrintGuides
    }

    let pages: [Page]
    let scale: CGFloat
    var color: Color = .accentColor

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path(CGRect.union(of: pages.map { scaled($0.guides.bleed, $0.origin) }))
                .stroke(color.opacity(0.75), lineWidth: 0.75)
            ForEach(pages.indices, id: \.self) { index in
                // A print service's binding margin is tinted and the dashed line follows it.
                ForEach(pages[index].guides.zones.indices, id: \.self) { zone in
                    Path(scaled(pages[index].guides.zones[zone].rect, pages[index].origin))
                        .fill(color.opacity(0.07))
                }
                Path(scaled(pages[index].guides.textSafe, pages[index].origin))
                    .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scaled(_ rect: CGRect, _ origin: CGPoint) -> CGRect {
        CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }
}

extension CGRect {
    /// The smallest rectangle holding all of them; the null rectangle for none.
    static func union(of rects: [CGRect]) -> CGRect {
        rects.reduce(CGRect.null) { $0.union($1) }
    }
}

/// The legend appears the first time the guides are turned on in a session.
@MainActor
enum PrintGuidesLegend {
    static var shown = false
}
