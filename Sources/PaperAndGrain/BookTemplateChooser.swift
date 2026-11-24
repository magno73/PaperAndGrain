import AppKit
import SwiftUI

struct BookTemplateChooser: View {
    let book: Book
    let directory: URL
    let language: String
    let onCancel: () -> Void
    let onApply: (BookTemplate?) -> Void

    @State private var selected: BookTemplate
    @State private var hero: NSImage?

    init(book: Book, directory: URL, language: String, onCancel: @escaping () -> Void,
         onApply: @escaping (BookTemplate?) -> Void) {
        self.book = book
        self.directory = directory
        self.language = language
        self.onCancel = onCancel
        self.onApply = onApply
        _selected = State(initialValue: book.template ?? .diary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("Modelli del libro", "Book Templates"))
                    .font(.system(size: 33, weight: .regular, design: .serif))
                Text(tr("Scegli carta, caratteri e margini per tutto il libro.", "Choose the paper, type and margins for the entire book."))
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 15), GridItem(.flexible())], spacing: 15) {
                    ForEach(BookTemplate.allCases) { option in
                        card(option)
                    }
                }
                .padding(4)
            }
            .frame(height: min(455, (NSScreen.main?.visibleFrame.height ?? 800) * 0.54))
            HStack {
                if book.template != nil {
                    Button(tr("Ripristina stile di base", "Restore Basic Style")) { onApply(nil) }
                        .buttonStyle(.link)
                }
                Spacer()
                Button(tr("Annulla", "Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(tr("Applica modello", "Apply Template")) { onApply(selected) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.19, green: 0.34, blue: 0.27))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 835)
        .task {
            let photo = book.cover?.frontPhotoID.flatMap(book.photo) ?? book.photos.first
            let source = photo.map { BookStorage.assetURL(filename: $0.filename, in: directory) }
                ?? Bundle.main.url(forResource: "Demo", withExtension: "png")
            if let source, let image = await Task.detached(operation: {
                LocalImages.load(source, maxPixelSize: 900)
            }).value {
                hero = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
    }

    private func card(_ option: BookTemplate) -> some View {
        let active = option == selected
        return Button { selected = option } label: {
            VStack(alignment: .leading, spacing: 13) {
                templatePreview(option)
                .frame(height: 113)
                .clipped()
                .shadow(color: .black.opacity(0.17), radius: 4, y: 2)
                .accessibilityHidden(true)
                HStack {
                    Text(option.name(language: language)).font(.system(size: 19, design: .serif))
                    Spacer()
                    if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.19, green: 0.34, blue: 0.27)) }
                }
                Text(option.description(language: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 45, alignment: .topLeading)
            }
            .padding(12)
            .background(active ? Color.accentColor.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(active ? Color.accentColor : Color.secondary.opacity(0.25)) }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func templatePreview(_ option: BookTemplate) -> some View {
        var sample = book
        sample.template = option
        let style = option.style
        let face = BookCoverGeometry(book: sample, front: true)
        let overPhoto = style.identity != nil
        let excerpt = book.pages.first(where: { !$0.text.isEmpty })?.text
            ?? tr("La luce attraversa il paesaggio.", "Light moves across the landscape.")
        let page = BookPage(layout: overPhoto ? .mixed : .text, text: String(excerpt.prefix(190)),
                            heading: book.pages.lazy.compactMap(\.heading).first ?? book.title,
                            arrangement: overPhoto ? .textOverPhoto : nil)
        let interior = PageComposition(page: page, book: sample)
        let blocks = interior.storyDrawingBlocks(page: page, book: sample)
        return Canvas { context, size in
            let scale = min((size.width - 5) / (2 * face.bounds.width), size.height / face.bounds.height)
            let paper = Color(cgColor: EditorialStyle.color(style.paper))
            context.translateBy(x: (size.width - 2 * face.bounds.width * scale - 5) / 2,
                                y: (size.height - face.bounds.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.fill(Path(face.bounds), with: .color(paper))
            if let hero {
                var clipped = context
                clipped.clip(to: Path(face.bounds))
                drawPreviewPhoto(hero, in: face.photoFrame, crop: face.photoCrop, fills: face.fills, context: clipped)
            }
            if let rule = face.rule { context.fill(Path(rule), with: .color(Color(cgColor: EditorialStyle.color(style.accent)))) }
            if let frame = face.titleFrame {
                context.withCGContext { cg in _ = EditorialTypesetter.draw(face.title, in: frame, context: cg) }
            }
            context.translateBy(x: face.bounds.width + 5 / scale, y: 0)
            context.fill(Path(interior.bounds), with: .color(paper))
            if overPhoto {
                if let hero { drawPreviewPhoto(hero, in: interior.bounds, context: context) }
                for panel in interior.storyBackgroundFrames(page: page, blocks: blocks) {
                    context.fill(Path(panel), with: .color(Color(cgColor: EditorialStyle.color(style.overlayPaper)).opacity(style.overlayOpacity)))
                    if let mark = style.overlayMark(in: panel) {
                        context.fill(Path(mark), with: .color(Color(cgColor: EditorialStyle.color(style.overlayAccent))))
                    }
                }
            }
            if let rule = interior.rule { context.fill(Path(rule), with: .color(Color(cgColor: EditorialStyle.color(style.accent)))) }
            context.withCGContext { cg in
                for block in blocks { EditorialTypesetter.draw(block.text, in: block.frame, context: cg) }
            }
        }
    }

    private func drawPreviewPhoto(_ photo: NSImage, in frame: CGRect, crop: PhotoCrop = PhotoCrop(),
                                  fills: Bool = true, context: GraphicsContext) {
        let placement = crop.imageRect(for: photo.size, in: frame, fills: fills)
        guard !placement.isEmpty else { return }
        var clipped = context
        clipped.clip(to: Path(frame))
        clipped.draw(Image(nsImage: photo), in: placement)
    }

    private func tr(_ italian: String, _ english: String) -> String { language == "it" ? italian : english }
}
