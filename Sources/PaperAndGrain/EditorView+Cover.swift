import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    @ViewBuilder func coverCanvas(_ side: CoverSide, scale: CGFloat, thumbnail: Bool = false) -> some View {
        let page = BookCoverGeometry(book: book, front: side == .front)
        let bounds = scaled(page.bounds, by: scale)
        let photo = coverPhotoID(side).flatMap(indexedPhoto)
        let surface = EditorDropTarget.cover(front: side == .front)
        let activeCrop = thumbnail || cropSession?.surface != surface ? nil : cropSession
        let photoTargets = [page.titleFrame, page.band].compactMap { $0 }.map { scaled($0, by: scale) }
        let content = ZStack(alignment: .topLeading) {
            Color(cgColor: EditorialStyle.color(page.background))
            if let photo {
                if thumbnail {
                    positioned(preview(photo, small: true, crop: page.photoCrop, fills: page.fills),
                               in: scaled(page.photoFrame, by: scale))
                } else if activeCrop == nil {
                    coverPhotoControl(photo, side: side, geometry: page, bounds: bounds, scale: scale,
                                      targets: photoTargets)
                }
            } else if !thumbnail {
                positioned(placeholder, in: scaled(page.photoFrame, by: scale))
            } else if side == .back {
                Image(systemName: "book.closed")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(cgColor: EditorialStyle.color(book.editorialStyle.accent)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let band = page.band {
                positioned(Color(white: 0.97, opacity: 0.94), in: scaled(band, by: scale))
                    .allowsHitTesting(false)
            }
            if let rule = page.rule {
                positioned(Color(cgColor: EditorialStyle.color(book.editorialStyle.accent)), in: scaled(rule, by: scale))
            }
            if let title = page.titleFrame {
                if thumbnail {
                    positioned(editorialText(page.title, scale: scale), in: scaled(title, by: scale))
                } else {
                    coverEditorialText(side, geometry: page, frame: scaled(title, by: scale), bounds: bounds, scale: scale)
                }
            }
            if let activeCrop, let photo {
                canvasCrop(activeCrop, photo: photo, bounds: bounds, scale: scale, alignmentTargets: photoTargets)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .clipped()
        if thumbnail {
            content.accessibilityHidden(true)
        } else {
            let label = coverName(side)
            content
                .contentShape(Rectangle())
                .accessibilityLabel(label)
                .overlayPreferenceValue(CanvasGuidePreference.self) { guides in
                    CanvasAlignmentGuides(guides: guides).allowsHitTesting(false)
                }
                .editorDropFrame(surface)
                .preference(key: CanvasHitMaps.self, value: [surface: .cover(
                    page, photoID: photo?.id, cropFrame: activeCrop?.frame.photoRect(in: page.bounds)
                )])
                .overlay {
                    if isPhotoDropTarget(.cover(front: side == .front)) {
                        Rectangle().strokeBorder(pine, lineWidth: 2).allowsHitTesting(false)
                    }
                }
        }
    }

    func coverPhotoControl(_ photo: BookPhoto, side: CoverSide, geometry: BookCoverGeometry,
                                   bounds: CGRect, scale: CGFloat, targets: [CGRect]) -> some View {
        let active = canvasPhotoSelection?.surface == .cover(front: side == .front)
            && canvasPhotoSelection?.photoID == photo.id
        return CanvasObjectControl(frame: scaled(geometry.photoFrame, by: scale), bounds: bounds, selected: active,
                                   minimumSize: CGSize(width: 40 * scale, height: 40 * scale),
                                   accessibilityName: photo.name, alignmentTargets: targets,
                                   allowsPhotoOverflow: true, preservesAspectRatio: true,
                                   onDoubleClick: { beginCoverCrop(side) },
                                   onSelect: { activateCanvas { selectCoverPhoto(photo.id) } },
                                   onNudge: { nudgeFromKeyboard($0) { selectCoverPhoto(photo.id) } },
                                   onChange: { frame in
            changeCoverPhotoPlacement(side, name: tr("Sposta o ridimensiona foto", "Move or Resize Photo")) {
                $0.frame = PageRect(frame, in: bounds).photoClamped
            }
        }) { _ in
            preview(photo, crop: geometry.photoCrop, fills: geometry.fills)
        }
        .accessibilityAction(named: Text(tr("Ritaglia foto", "Crop Photo"))) { beginCoverCrop(side) }
    }

    func coverEditorialText(_ side: CoverSide, geometry: BookCoverGeometry, frame: CGRect,
                                    bounds: CGRect, scale: CGFloat) -> some View {
        let style = book.editorialStyle
        let front = side == .front
        let defaults = front && book.template != nil ? style.defaultTitleStyle(mixed: false) : style.defaultBodyStyle
        let override = book.coverTextStyle(front: front)
        let value = coverEditorialValue(side)
        let type = defaults.applying(front && book.template != nil
            ? style.fittedTitleStyle(value.wrappedValue, width: frame.width / scale, mixed: false, override: override)
            : override)
        return editableEditorialObject(.cover(side), content: geometry.title, value: value,
                                       type: type, label: front ? tr("Titolo", "Title") : tr("Testo del retro", "Back Cover Text"),
                                       frame: frame, bounds: bounds, scale: scale,
                                       targets: [scaled(geometry.photoFrame.intersection(geometry.bounds), by: scale)],
                                       textInk: front ? style.titleInk : style.ink,
                                       onSelect: { selectEditorial(.cover(side)) },
                                       onChange: { moveCoverText(side, to: PageRect($0, in: bounds)) })
    }

    func coverInspector(_ side: CoverSide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            caption(coverName(side))
            if side == .front {
                TextField(tr("Titolo in copertina", "Cover Title"), text: Binding(
                    get: { book.cover?.title ?? book.title },
                    set: { value in changeCover { $0.title = value } }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($writing)
            } else {
                TextEditor(text: Binding(
                    get: { book.cover?.backText ?? "" },
                    set: { value in changeCover { $0.backText = value.isEmpty ? nil : value } }
                ))
                .font(.system(size: 14, design: .serif))
                .scrollContentBackground(.hidden)
                .focused($writing)
                .padding(5)
                .frame(minHeight: 100)
                .background(paper, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(tr("Testo del retro", "Back Cover Text"))
            }
            // Font, size and color live in the Text tab, as for every other text in the book.
            Button {
                selectEditorial(.cover(side))
                showInspectorTab(.text)
            } label: {
                Label(tr("Carattere e paragrafo", "Font and Paragraph"), systemImage: "textformat")
            }
            if (side == .front ? book.cover?.frontTitleFrame : book.cover?.backTextFrame) != nil {
                Button(tr("Ripristina posizione del testo", "Reset Text Placement")) { moveCoverText(side, to: nil) }
            }
            Divider()
            caption(tr("Foto", "Photo"))
            if let photo = coverPhotoID(side).flatMap(indexedPhoto) {
                // Selecting the photo opens the Photo tab with adjustments and film look.
                Button {
                    selectCoverPhoto(photo.id)
                    showInspectorTab(.photo)
                } label: {
                    HStack(spacing: 8) {
                        preview(photo, small: true).frame(width: 38, height: 30).clipped()
                        Text(photo.name).font(.callout).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Seleziona la foto per regolarla", "Select the photo to adjust it"))
                if coverPhotoPlacement(side) != nil {
                    Button(localized("editor.cover.reset_photo", fallback: "Reset Photo Placement and Crop")) {
                        changeCoverPhotoPlacement(side, name: tr("Ripristina foto di copertina", "Reset Cover Photo")) {
                            $0 = PhotoPlacement()
                        }
                    }
                }
            }
            Button(tr("Scegli foto", "Choose Photo"), systemImage: "photo.on.rectangle", action: browsePhotos)
            if book.cover == nil {
                Button(tr("Aggiungi copertina al libro", "Add Cover to Book")) { changeCover { _ in } }
            }
        }
    }

    func coverTextStyle(_ key: WritableKeyPath<EditorialTypography, EditorialTextStyle?>)
        -> Binding<EditorialTextStyle?> {
        Binding(
            get: { book.cover?.typography?[keyPath: key] },
            set: { value in
                var type = book.cover?.typography ?? EditorialTypography()
                guard type[keyPath: key] != value else { return }
                type[keyPath: key] = value
                let previous = book.cover?.typography
                changeCover { $0.typography = type.title == nil && type.body == nil ? nil : type }
                if let undoManager {
                    undoTarget.registerCoverValue(undoManager, binding: $book, bookID: book.id, key: \.typography,
                                                  previous: previous, name: tr("Modifica tipografia", "Change Typography"))
                }
            }
        )
    }

    func selectCover(_ side: CoverSide) {
        guard coverSide != side else { return }
        finishCrop()
        endInlineTextEditing()
        coverSide = side
        canvasPhotoSelection = nil
        selectedPhoto = nil
        selectedBox = nil
        selectedEditorial = nil
        writing = false
        writingBox = false
        filmScope = .book
        inspector = .page
    }

    func selectCoverPhoto(_ id: UUID) {
        endInlineTextEditing()
        writing = false
        writingBox = false
        selectedPhoto = id
        selectedBox = nil
        selectedEditorial = nil
        if let coverSide {
            canvasPhotoSelection = CanvasPhotoSelection(surface: .cover(front: coverSide == .front), photoID: id)
        }
        searchingPhotos = false
    }

    func changeCover(_ change: (inout BookCover) -> Void) {
        var cover = book.cover ?? BookCover(title: book.title)
        change(&cover)
        book.cover = cover
    }

    func coverPlacementKey(_ side: CoverSide) -> WritableKeyPath<BookCover, PhotoPlacement?> {
        side == .front ? \.frontPhotoPlacement : \.backPhotoPlacement
    }

    func coverPhotoPlacement(_ side: CoverSide) -> PhotoPlacement? {
        book.cover?[keyPath: coverPlacementKey(side)]
    }

    func changeCoverPhotoPlacement(_ side: CoverSide, name: String,
                                           _ edit: (inout PhotoPlacement) -> Void) {
        let key = coverPlacementKey(side)
        let previous = coverPhotoPlacement(side)
        var placement = previous ?? PhotoPlacement()
        edit(&placement)
        let next = placement == PhotoPlacement() ? nil : placement
        guard next != previous else { return }
        changeCover { $0[keyPath: key] = next }
        if let undoManager {
            undoTarget.registerCoverValue(undoManager, binding: $book, bookID: book.id, key: key, previous: previous, name: name)
        }
    }

    func setCoverPhoto(_ id: UUID?, side: CoverSide) {
        finishCrop()
        let key: WritableKeyPath<BookCover, UUID?> = side == .front ? \.frontPhotoID : \.backPhotoID
        let placement = coverPlacementKey(side)
        let previous = CoverImage(id: coverPhotoID(side), placement: coverPhotoPlacement(side))
        if previous.id != id {
            changeCover {
                $0[keyPath: key] = id
                $0[keyPath: placement] = nil
            }
            if let undoManager {
                undoTarget.registerCoverImage(undoManager, binding: $book, bookID: book.id,
                                             idKey: key, placementKey: placement, previous: previous,
                                             name: id == nil ? tr("Rimuovi foto di copertina", "Remove Cover Photo")
                                                 : tr("Imposta foto di copertina", "Set Cover Photo"))
            }
        }
        if let id { selectCoverPhoto(id) }
        else { clearCanvasSelection() }
    }

    func coverEditorialValue(_ side: CoverSide) -> Binding<String> {
        Binding(
            get: { side == .front ? book.cover?.title ?? book.title : book.cover?.backText ?? "" },
            set: { value in
                changeCover {
                    if side == .front { $0.title = value }
                    else { $0.backText = value.isEmpty ? nil : value }
                }
            }
        )
    }

    func moveCoverText(_ side: CoverSide, to frame: PageRect?) {
        let key: WritableKeyPath<BookCover, PageRect?> = side == .front ? \.frontTitleFrame : \.backTextFrame
        let previous = book.cover?[keyPath: key]
        let next = frame?.clamped
        guard previous != next else { return }
        changeCover { $0[keyPath: key] = next }
        if let undoManager {
        undoTarget.registerCoverValue(undoManager, binding: $book, bookID: book.id, key: key, previous: previous,
                                          name: tr("Sposta o ridimensiona testo", "Move or Resize Text"))
        }
    }

    func beginCoverCrop(_ side: CoverSide) {
        finishCrop()
        guard let id = coverPhotoID(side) else { return }
        let geometry = BookCoverGeometry(book: book, front: side == .front)
        selectCoverPhoto(id)
        let frame = PageRect(geometry.photoFrame, in: geometry.bounds)
        cropSession = CropSession(surface: .cover(front: side == .front), photoID: id, initialFrame: frame,
                                  initialCrop: geometry.photoCrop, frame: frame, crop: geometry.photoCrop)
    }
}
