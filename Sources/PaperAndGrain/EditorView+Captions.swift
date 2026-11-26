import AppKit
import SwiftUI

/// Photo captions in the editor: the Photo tab's field and position, in-place typing on the canvas,
/// filling from place and date, and the caption drawn with its photo. Geometry comes from
/// `PageComposition.captions`; nothing here lays a caption out on its own.
extension EditorView {
    /// The caption text of a photo, wherever it is placed. Typing is undone like other text.
    func captionValue(_ photoID: UUID) -> Binding<String> {
        Binding(
            get: { indexedPhoto(photoID)?.caption ?? "" },
            set: { value in
                guard let index = photoIndex(photoID) else { return }
                let next: String? = value.isEmpty ? nil : value
                if book.photos[index].caption != next { book.photos[index].caption = next }
            }
        )
    }

    /// "Place, 12 May 2024" from the photo's place and capture date, in the interface language.
    func automaticCaption(for photo: BookPhoto) -> String? {
        CaptionText.automatic(place: photo.location?.name ?? placesRead[photo.id]?.name, date: photo.capturedAt,
                              language: language)
    }

    func fillCaption(_ photoID: UUID) {
        guard let index = photoIndex(photoID), let text = automaticCaption(for: book.photos[index]) else { return }
        let previous = book.photos[index].caption
        guard previous != text else { return }
        book.photos[index].caption = text
        if let undoManager {
            undoTarget.registerPhotoValue(undoManager, binding: $book, bookID: book.id, photoID: photoID,
                                          key: \.caption, previous: previous, name: tr("Fill Caption"))
        }
    }

    /// The captions **Caption Photos on This Page** would write: photos on the page with no caption
    /// and a place or a date.
    func automaticCaptions(on leaf: BookPage) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for id in leaf.photoIDs {
            guard let photo = indexedPhoto(id), photo.printedCaption == nil,
                  let text = automaticCaption(for: photo) else { continue }
            result[id] = text
        }
        return result
    }

    func captionPhotosOnPage() {
        guard coverSide == nil, let page else { return }
        let captions = automaticCaptions(on: page)
        guard !captions.isEmpty else {
            showCanvasNotice(tr("No photo on this page needs a caption with a place or date."))
            return
        }
        var previous: [UUID: String?] = [:]
        for (id, text) in captions {
            guard let index = photoIndex(id) else { continue }
            previous[id] = book.photos[index].caption
            book.photos[index].caption = text
        }
        if let undoManager {
            undoTarget.registerCaptions(undoManager, binding: $book, bookID: book.id, previous: previous,
                                        name: tr("Caption Photos"))
        }
        showCanvasNotice(tr("%lld captions filled.", previous.count))
    }

    func captionPosition(_ photoID: UUID, on pageID: UUID) -> CaptionPosition? {
        book.pages.first { $0.id == pageID }?.photoPlacements?[photoID]?.captionPosition
    }

    /// Changes where this page shows the caption; nil is automatic.
    func setCaptionPosition(_ position: CaptionPosition?, for photoID: UUID, on pageID: UUID) {
        guard let index = book.pages.firstIndex(where: { $0.id == pageID }),
              book.pages[index].photoIDs.contains(photoID),
              captionPosition(photoID, on: pageID) != position else { return }
        editPages(tr("Caption Position")) { pages in
            var placements = pages[index].photoPlacements ?? [:]
            var placement = placements[photoID] ?? PhotoPlacement()
            placement.captionPosition = position
            placements[photoID] = placement == PhotoPlacement() ? nil : placement
            pages[index].photoPlacements = placements.isEmpty ? nil : placements
        }
    }

    /// Selects the photo and types its caption on the page.
    func beginCaptionEditing(_ photoID: UUID, in leaf: BookPage) {
        guard let current = book.pages.first(where: { $0.id == leaf.id }), current.photoIDs.contains(photoID) else { return }
        selectCanvasPhoto(photoID, in: current)
        editorInput.target = .canvas
        editingEditorial = .caption(page: current.id, photo: photoID)
    }

    func captionName(_ position: CaptionPosition?) -> String {
        switch position {
        case nil: tr("Automatic", key: "caption.automatic")
        case .below?: tr("Below")
        case .above?: tr("Above")
        case .inside?: tr("On Photo")
        case .hidden?: tr("Hidden")
        }
    }

    /// The Photo tab's caption: the text, shared by every page, and where this page shows it.
    @ViewBuilder func captionInspector(_ photo: BookPhoto) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            caption(tr("Caption"))
            TextField(tr("Caption"), text: captionValue(photo.id),
                      prompt: Text(tr("Place, date or a few words")), axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(tr("Caption"))
                .help(tr("Printed with the photo on every page where it appears"))
            if let selection = canvasPhotoSelection, selection.photoID == photo.id, let pageID = selection.pageID {
                Picker(tr("Position"), selection: Binding(
                    get: { captionPosition(photo.id, on: pageID) },
                    set: { setCaptionPosition($0, for: photo.id, on: pageID) }
                )) {
                    ForEach([nil] + CaptionPosition.allCases.map(Optional.some), id: \.self) { position in
                        Text(captionName(position)).tag(position)
                    }
                }
                .accessibilityLabel(tr("Caption Position"))
                .help(tr("Where this page shows the caption. Automatic puts it below the photo, or on the photo when there is no room."))
            }
            Button {
                fillCaption(photo.id)
            } label: {
                Label(tr("Fill from Place and Date"), systemImage: "mappin.and.ellipse")
            }
            .disabled(automaticCaption(for: photo) == nil)
            .help(tr("Write the photo’s place and capture date as its caption"))
        }
    }

    /// The caption over the page, following the photo's frame as it is shown now (also during a drag).
    func canvasCaption(_ caption: PageComposition.Caption, photoFrame: CGRect, shown: CGRect, scale: CGFloat,
                       leaf: BookPage) -> some View {
        let style = book.editorialStyle
        let text = Self.following(scaled(caption.frame, by: scale), from: photoFrame, to: shown)
        let band = caption.band.map { Self.following(scaled($0, by: scale), from: photoFrame, to: shown) }
        let edit = { beginCaptionEditing(caption.photoID, in: leaf) }
        return ZStack(alignment: .topLeading) {
            if let band {
                // The hit area is the band itself, never the whole page the positioned view spans.
                positioned(Rectangle().fill(Color(cgColor: EditorialStyle.color(style.overlayPaper)))
                    .opacity(style.overlayOpacity).contentShape(Rectangle()), in: band)
                    .onTapGesture(count: 2, perform: edit)
                    .accessibilityHidden(true)
            }
            positioned(editorialText(caption.text, scale: scale).contentShape(Rectangle()), in: text)
                .onTapGesture(count: 2, perform: edit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("Caption") + ": " + caption.text.string)
                .accessibilityAction(named: Text(tr("Edit Caption")), edit)
        }
    }

    /// A caption rectangle carried from where the photo was to where it is shown: it keeps its
    /// distance from the nearer edge, and its share of the width.
    static func following(_ rect: CGRect, from old: CGRect, to new: CGRect) -> CGRect {
        guard old != new, old.width > 0 else { return rect }
        let sx = new.width / old.width
        let x = new.minX + (rect.minX - old.minX) * sx
        let y = rect.minY >= old.midY ? new.maxY + (rect.minY - old.maxY) : new.minY + (rect.minY - old.minY)
        return CGRect(x: x, y: y, width: rect.width * sx, height: rect.height)
    }

    /// Typing a caption on the page, over everything else, like a text box.
    @ViewBuilder func canvasCaptionEditor(_ leaf: BookPage, composition: PageComposition, scale: CGFloat) -> some View {
        if case let .caption(pageID, photoID)? = editingEditorial, pageID == leaf.id,
           let item = composition.photos.first(where: { $0.id == photoID }) {
            let style = book.editorialStyle
            let type = style.defaultCaptionStyle.applying(book.captionStyle)
            let caption = composition.caption(for: photoID)
            let frame = captionEditingFrame(caption, photo: item.frame, in: composition)
            let onPhoto = caption?.position == .inside || caption == nil
            let font = type.fontName.flatMap { NSFont(name: $0, size: 12)?.fontName } ?? style.bodyFont
            let alignment: TextAlignment = type.alignment == .center ? .center : (type.alignment == .right ? .trailing : .leading)
            let object = EditorialObject.caption(page: leaf.id, photo: photoID)
            positioned(
                TextEditor(text: captionValue(photoID))
                    .font(.custom(font, size: max(1, (type.pointSize ?? style.bodySize) * scale)))
                    .multilineTextAlignment(alignment)
                    .foregroundStyle(Color(cgColor: EditorialStyle.color(
                        type.color ?? (onPhoto ? style.overlayCaptionInk : style.captionInk))))
                    .scrollContentBackground(.hidden)
                    .background(Color(cgColor: EditorialStyle.color(onPhoto ? style.overlayPaper : style.paper)))
                    .overlay { Rectangle().strokeBorder(pine, lineWidth: 1.5).allowsHitTesting(false) }
                    .focused($editorialFocus, equals: object)
                    .accessibilityLabel(tr("Caption"))
                    .onExitCommand(perform: endInlineTextEditing)
                    .task(id: object) {
                        await Task.yield()
                        if NSApp.isActive && editingEditorial == object { editorialFocus = object }
                    },
                in: scaled(frame, by: scale))
        }
    }

    /// Where the caption is typed: its own frame, or for a new caption two lines at the bottom of the
    /// photo, a little taller than the text so the cursor never hides.
    func captionEditingFrame(_ caption: PageComposition.Caption?, photo: CGRect,
                             in composition: PageComposition) -> CGRect {
        let style = book.editorialStyle
        let size = book.captionStyle.normalizedSize ?? style.defaultCaptionStyle.pointSize ?? style.bodySize
        let minimum = size * 2.6
        if let caption {
            let frame = caption.frame
            return CGRect(x: frame.minX - 4, y: frame.minY - 3, width: frame.width + 8,
                          height: max(minimum, frame.height + 6))
        }
        let visible = photo.intersection(composition.bounds)
        guard !visible.isNull else { return .zero }
        return CGRect(x: visible.minX, y: max(visible.minY, visible.maxY - minimum), width: visible.width,
                      height: min(minimum, visible.height))
    }

    /// The caption in a thumbnail or **Browse the Book**, at the composition's scale.
    func miniCaption(_ caption: PageComposition.Caption, scale: CGFloat) -> some View {
        let style = book.editorialStyle
        return ZStack(alignment: .topLeading) {
            if let band = caption.band {
                positioned(Color(cgColor: EditorialStyle.color(style.overlayPaper)).opacity(style.overlayOpacity),
                           in: scaled(band, by: scale))
            }
            positioned(editorialText(caption.text, scale: scale), in: scaled(caption.frame, by: scale))
        }
    }
}
