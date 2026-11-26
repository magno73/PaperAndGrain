import AppKit
import CoreGraphics
import Foundation

/// Objects of a page on the pasteboard, as the private type `me.magno.paperandgrain.objects` (JSON).
/// Frames are in the source page's points, from its top left; the source page size travels with them.
/// Text boxes and the story also go on the pasteboard as plain text, for other apps.
struct CanvasClipboard: Codable, Equatable, Sendable {
    static let pasteboardType = NSPasteboard.PasteboardType("me.magno.paperandgrain.objects")
    static let currentVersion = 1
    /// Text boxes pasted on the page they were copied from (and duplicates) move this far down and right.
    static let sameSpotOffset: CGFloat = 12

    var version = Self.currentVersion
    var bookID: UUID
    var pageID: UUID
    var pageWidth: Double
    var pageHeight: Double
    /// Back to front.
    var objects: [Object]

    /// A photo and its whole placement on the page (crop, caption position and whatever comes later);
    /// `frame` is where it was drawn, in points.
    struct Photo: Codable, Equatable, Sendable {
        var photoID: UUID
        var frame: CGRect
        var placement: PhotoPlacement?
    }

    struct Box: Codable, Equatable, Sendable {
        var box: PageTextBox
        var frame: CGRect
    }

    struct Story: Codable, Equatable, Sendable {
        var heading: String?
        var text: String
        var typography: EditorialTypography?
        /// The heading's and the story's frames as drawn, and the backdrop behind them.
        var titleFrame: CGRect?
        var bodyFrame: CGRect?
        var backdropFrames: [CGRect]?
        /// Where the whole story sits: used when it pastes as a text box.
        var extent: CGRect

        /// Heading and story as one text, for a text box or another app.
        var plainText: String {
            let heading = heading?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return [heading, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }

    enum Object: Equatable, Sendable {
        case photo(Photo)
        case textBox(Box)
        case story(Story)
    }

    /// The text other apps receive: text boxes and the story, back to front, one paragraph apart.
    var plainText: String? {
        let parts = objects.compactMap { object -> String? in
            switch object {
            case .photo: nil
            case let .textBox(item): item.box.text.isEmpty ? nil : item.box.text
            case let .story(story): story.plainText.isEmpty ? nil : story.plainText
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    // MARK: Copy

    /// The selected layers of `page`, in drawing order. Nil when none of them is on the page.
    init?(layers: [PageLayer], page: BookPage, book: Book) {
        let composition = PageComposition(page: page, book: book)
        let chosen = Set(layers)
        var objects: [Object] = []
        for layer in composition.layers where chosen.contains(layer) {
            switch layer {
            case let .photo(id):
                guard let item = composition.photos.first(where: { $0.id == id }) else { continue }
                objects.append(.photo(Photo(photoID: id, frame: item.frame, placement: page.photoPlacements?[id])))
            case let .textBox(id):
                guard let box = composition.textBoxes.first(where: { $0.id == id }) else { continue }
                objects.append(.textBox(Box(box: box, frame: box.frame.rect(in: composition.bounds))))
            case .story:
                guard page.hasStoryText,
                      let extent = BookPage.storyExtent(of: page, book: book, in: composition) else { continue }
                let blocks = composition.storyBlocks(page: page, book: book)
                let backings = composition.storyBackgroundFrames(page: page, blocks: blocks)
                objects.append(.story(Story(
                    heading: page.heading, text: page.text, typography: page.typography,
                    titleFrame: blocks.first { $0.role == .title && !$0.frame.isEmpty }?.frame,
                    bodyFrame: blocks.first { $0.role == .body && !$0.frame.isEmpty }?.frame,
                    backdropFrames: backings.isEmpty ? nil : backings, extent: extent)))
            }
        }
        guard !objects.isEmpty else { return nil }
        self.init(bookID: book.id, pageID: page.id, pageWidth: composition.bounds.width,
                  pageHeight: composition.bounds.height, objects: objects)
    }

    init(bookID: UUID, pageID: UUID, pageWidth: Double, pageHeight: Double, objects: [Object]) {
        self.bookID = bookID
        self.pageID = pageID
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.objects = objects
    }

    // MARK: Paste

    /// Why a photo was left out of a paste.
    enum Skipped: Equatable, Sendable {
        /// The photo is already on the page; a page holds a photo once.
        case alreadyOnPage
        /// The photo belongs to another book: its image file is not in this one.
        case otherBook
        /// The photo was removed from this book after it was copied.
        case notInBook
    }

    struct Pasted: Equatable {
        var page: BookPage
        /// The objects added, back to front; they become the selection.
        var layers: [PageLayer]
        var skipped: [Skipped]
    }

    /// Adds the objects to `page`. Frames keep their place relative to the page (moved inside it when the
    /// page is smaller); on the page they come from, text boxes move 12 pt down and right so they show.
    /// Photos already on the page or from another book are skipped. The story becomes the page's story when
    /// it has none, otherwise a text box. Text boxes get new ids. The pasted objects go on top, in order.
    func paste(into page: BookPage, book: Book) -> Pasted {
        let bounds = PageComposition(page: page, book: book).bounds
        let sameBook = bookID == book.id
        let samePage = sameBook && pageID == page.id
        let shift: CGFloat = samePage ? Self.sameSpotOffset : 0
        let before = page.stackingOrder(photos: page.photoIDs, boxes: page.textBoxes?.map(\.id) ?? [])
        var result = page
        var layers: [PageLayer] = []
        var skipped: [Skipped] = []
        func inside(_ rect: CGRect) -> CGRect { Self.kept(rect, in: bounds) }
        for object in objects {
            switch object {
            case let .photo(item):
                guard sameBook else { skipped.append(.otherBook); continue }
                guard book.photo(item.photoID) != nil else { skipped.append(.notInBook); continue }
                guard !result.photoIDs.contains(item.photoID) else { skipped.append(.alreadyOnPage); continue }
                result.photoIDs.append(item.photoID)
                var placements = result.photoPlacements ?? [:]
                var placement = item.placement ?? PhotoPlacement()
                placement.frame = PageRect(Self.visible(item.frame, in: bounds), in: bounds).photoClamped
                placements[item.photoID] = placement
                result.photoPlacements = placements
                layers.append(.photo(item.photoID))
            case let .textBox(item):
                var box = item.box
                box.id = UUID()
                box.frame = PageRect(inside(item.frame.offsetBy(dx: shift, dy: shift)), in: bounds).clamped
                result.textBoxes = (result.textBoxes ?? []) + [box]
                layers.append(.textBox(box.id))
            case let .story(story):
                if !result.hasStoryText {
                    result.heading = story.heading
                    result.text = story.text
                    result.typography = story.typography
                    result.titleFrame = story.titleFrame.map { PageRect(inside($0), in: bounds).clamped }
                    result.storyFrame = story.bodyFrame.map { PageRect(inside($0), in: bounds).clamped }
                    result.storyBackdropFrames = story.backdropFrames.map { $0.map { PageRect(inside($0), in: bounds) } }
                    layers.append(.story)
                } else {
                    var box = PageTextBox(text: story.plainText,
                                          frame: PageRect(inside(story.extent.offsetBy(dx: shift, dy: shift)), in: bounds).clamped)
                    box.typography = story.typography?.body
                    result.textBoxes = (result.textBoxes ?? []) + [box]
                    layers.append(.textBox(box.id))
                }
            }
        }
        if !layers.isEmpty {
            result.layerOrder = before.filter { !layers.contains($0) } + layers
        }
        return Pasted(page: result, layers: layers, skipped: skipped)
    }

    /// A photo frame on the destination page: kept as it is while at least half of it shows (a photo that
    /// bleeds keeps its overflow), otherwise moved inside the page with its size, like a text frame.
    static func visible(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let shown = rect.intersection(bounds)
        let area = shown.isNull ? 0 : shown.width * shown.height
        return area >= rect.width * rect.height * 0.5 ? rect : kept(rect, in: bounds)
    }

    /// A rectangle moved inside `bounds` where it can be; one larger than the page keeps its top left on it.
    static func kept(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let x = rect.width > bounds.width ? bounds.minX : min(bounds.maxX - rect.width, max(bounds.minX, rect.minX))
        let y = rect.height > bounds.height ? bounds.minY : min(bounds.maxY - rect.height, max(bounds.minY, rect.minY))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// Plain text from another app: a new text box in the middle of the page.
    static func textBox(for text: String, in bounds: CGRect, safe: CGRect) -> PageTextBox {
        let width = min(safe.width, bounds.width * 0.62)
        let height = min(safe.height, bounds.height * 0.19)
        let frame = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        return PageTextBox(text: text, frame: PageRect(frame, in: bounds).clamped)
    }

    // MARK: Pasteboard

    func write(to pasteboard: NSPasteboard) throws {
        let data = try JSONEncoder().encode(self)
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [Self.pasteboardType]
        if plainText != nil { types.append(.string) }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setData(data, forType: Self.pasteboardType)
        if let plainText { pasteboard.setString(plainText, forType: .string) }
    }

    /// What a paste would bring: our objects, or plain text from another app.
    enum Contents: Equatable {
        case objects(CanvasClipboard)
        case text(String)
    }

    static func read(from pasteboard: NSPasteboard) -> Contents? {
        if let data = pasteboard.data(forType: pasteboardType),
           let clip = try? JSONDecoder().decode(CanvasClipboard.self, from: data), clip.version <= currentVersion {
            return .objects(clip)
        }
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return nil
    }

    /// True when a paste would bring something: objects this version can read, or plain text.
    static func canRead(from pasteboard: NSPasteboard) -> Bool {
        guard pasteboard.availableType(from: [pasteboardType, .string]) != nil else { return false }
        return read(from: pasteboard) != nil
    }

    /// Whether pasting on the page it came from adds anything: a text box or a story (which becomes a box
    /// there). Photos alone cannot be on their page twice.
    var duplicatesOnItsPage: Bool {
        objects.contains { if case .photo = $0 { false } else { true } }
    }
}

extension CanvasClipboard.Object: Codable {
    private enum CodingKeys: String, CodingKey { case kind, photo, textBox, story }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "photo": self = .photo(try container.decode(CanvasClipboard.Photo.self, forKey: .photo))
        case "textBox": self = .textBox(try container.decode(CanvasClipboard.Box.self, forKey: .textBox))
        case "story": self = .story(try container.decode(CanvasClipboard.Story.self, forKey: .story))
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown object \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .photo(item):
            try container.encode("photo", forKey: .kind)
            try container.encode(item, forKey: .photo)
        case let .textBox(item):
            try container.encode("textBox", forKey: .kind)
            try container.encode(item, forKey: .textBox)
        case let .story(story):
            try container.encode("story", forKey: .kind)
            try container.encode(story, forKey: .story)
        }
    }
}

extension BookPage {
    /// Takes the given objects off the page, as **Cut** does: photos (back to the Photo Library), text boxes,
    /// and the story's heading, text, frames and type style. A page's `typography` styles only its story,
    /// so it goes with it.
    mutating func removeObjects(_ layers: [PageLayer]) {
        for layer in layers {
            switch layer {
            case let .photo(id):
                photoIDs.removeAll { $0 == id }
                photoPlacements?.removeValue(forKey: id)
                if photoPlacements?.isEmpty == true { photoPlacements = nil }
            case let .textBox(id):
                textBoxes?.removeAll { $0.id == id }
                if textBoxes?.isEmpty == true { textBoxes = nil }
            case .story:
                heading = nil
                text = ""
                titleFrame = nil
                storyFrame = nil
                storyBackdropFrames = nil
                typography = nil
            }
        }
        if let order = layerOrder {
            let removed = Set(layers.filter { $0 != .story })
            let kept = order.filter { !removed.contains($0) }
            layerOrder = kept.isEmpty ? nil : kept
        }
    }
}
