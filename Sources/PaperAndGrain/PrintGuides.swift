import CoreGraphics
import Foundation

/// Where the knife falls on one page: the trim, the safe line inside it and the bleed line outside it,
/// in typographic points from the top left of the trim. One pure function builds them, and the canvas
/// overlay and the two preflight warnings (text outside the safe margin, photo ending near the edge)
/// read the same values. Print-service profiles add their own zones (hinge, inner margin, spine)
/// through `zones`.
struct PrintGuides: Equatable, Sendable {
    static let pointsPerMM = 72.0 / 25.4

    /// A photo edge closer to the trim than this counts as on the trim (millimetres).
    static let trimToleranceMM = 0.25

    /// An area of the page a print service keeps clear, or treats differently.
    struct Zone: Equatable, Sendable {
        enum Kind: String, Equatable, Sendable { case hinge, innerMargin, spine }
        var kind: Kind
        var rect: CGRect
    }

    enum Edge: CaseIterable, Sendable { case left, right, top, bottom }

    /// The page as it is cut.
    let trim: CGRect
    /// `safeMM` inside the trim: text stays inside it.
    let safe: CGRect
    /// `bleedMM` outside the trim: photos that reach the edge extend to it.
    let bleed: CGRect
    let bleedMM: Double
    let zones: [Zone]

    /// `pageSize` is the trim size in points (a full spread passes its double width).
    static func frames(pageSize: CGSize, settings: PrintSettings, zones: [Zone] = []) -> PrintGuides {
        let trim = CGRect(origin: .zero, size: pageSize)
        let safeMM = max(0, settings.safeMM)
        let bleedMM = max(0, settings.bleedMM)
        return PrintGuides(trim: trim,
                           safe: trim.insetBy(dx: safeMM * pointsPerMM, dy: safeMM * pointsPerMM),
                           bleed: trim.insetBy(dx: -bleedMM * pointsPerMM, dy: -bleedMM * pointsPerMM),
                           bleedMM: bleedMM, zones: zones)
    }

    /// True when `frame` lies inside the safe line (a hair of tolerance for rounding).
    func keepsInsideSafe(_ frame: CGRect) -> Bool {
        let slack = 0.01
        return frame.minX >= safe.minX - slack && frame.maxX <= safe.maxX + slack
            && frame.minY >= safe.minY - slack && frame.maxY <= safe.maxY + slack
    }

    /// Edges of a photo frame that stop inside the trim by more than 0.25 mm and less than the bleed:
    /// neither safely inside nor bleeding, so a small cutting error shows paper. The distance is in
    /// millimetres. Edges in `ignoring` are not cut (the binding edge of a page).
    func edgesNearTrim(of frame: CGRect, ignoring: Set<Edge> = []) -> [(edge: Edge, distanceMM: Double)] {
        guard !frame.isEmpty else { return [] }
        let gaps: [(Edge, CGFloat)] = [
            (.left, frame.minX - trim.minX), (.right, trim.maxX - frame.maxX),
            (.top, frame.minY - trim.minY), (.bottom, trim.maxY - frame.maxY),
        ]
        return gaps.compactMap { edge, gap in
            let mm = Double(gap) / Self.pointsPerMM
            guard !ignoring.contains(edge), mm > Self.trimToleranceMM, mm < bleedMM else { return nil }
            return (edge, mm)
        }
    }
}
