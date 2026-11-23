import CoreGraphics

/// Geometry of the supplied 21 × 21 cm hardcover template, in millimetres.
enum PixartPrintProfile {
    static let wrap = 19.0
    static let hinge = 11.0
    static let panelWidth = 207.0
    static let panelHeight = 220.0
    static let bleed = 3.0

    static func supports(_ format: BookFormat) -> Bool {
        abs(format.widthMM - 210) < 0.000001 && abs(format.heightMM - 210) < 0.000001
    }

    static func isValidSpine(_ mm: Double) -> Bool {
        mm.isFinite && mm > 0 && mm <= 100
    }
}
