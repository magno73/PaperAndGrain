import AppKit

enum EditorialAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, center, right, justified
    var id: Self { self }

    var paragraphAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        }
    }
}

struct EditorialTextStyle: Codable, Hashable, Sendable {
    static let pointSizeRange = 6.0...120.0
    static let lineSpacingRange = 0.8...2.0
    var fontName: String?
    var pointSize: Double?
    var alignment: EditorialAlignment?
    /// Text color as 0xRRGGBB; nil keeps the template's ink.
    var color: UInt32? = nil
    /// Line height multiple; nil keeps the template's leading.
    var lineSpacing: Double? = nil

    var normalizedLineSpacing: Double? {
        guard let lineSpacing, lineSpacing.isFinite else { return nil }
        return min(Self.lineSpacingRange.upperBound, max(Self.lineSpacingRange.lowerBound, lineSpacing))
    }

    var normalizedSize: Double? {
        guard let pointSize, pointSize.isFinite else { return nil }
        return min(Self.pointSizeRange.upperBound, max(Self.pointSizeRange.lowerBound, pointSize))
    }

    func applying(_ overrides: Self?) -> Self {
        (overrides ?? Self()).inheriting(self)
    }

    func inheriting(_ base: Self?) -> Self {
        Self(fontName: fontName ?? base?.fontName,
             pointSize: normalizedSize ?? base?.normalizedSize,
             alignment: alignment ?? base?.alignment,
             color: color ?? base?.color,
             lineSpacing: normalizedLineSpacing ?? base?.normalizedLineSpacing)
    }
}

struct EditorialTypography: Codable, Hashable, Sendable {
    var title: EditorialTextStyle?
    var body: EditorialTextStyle?
}

extension Book {
    func titleStyle(for page: BookPage) -> EditorialTextStyle {
        (page.typography?.title ?? EditorialTextStyle()).inheriting(typography?.title)
    }

    func bodyStyle(for page: BookPage) -> EditorialTextStyle {
        (page.typography?.body ?? EditorialTextStyle()).inheriting(typography?.body)
    }

    func bodyStyle(for box: PageTextBox) -> EditorialTextStyle {
        (box.typography ?? EditorialTextStyle()).inheriting(typography?.body)
    }

    func coverTextStyle(front: Bool) -> EditorialTextStyle {
        let face = front ? cover?.typography?.title : cover?.typography?.body
        return (face ?? EditorialTextStyle()).inheriting(front ? typography?.title : typography?.body)
    }
}
