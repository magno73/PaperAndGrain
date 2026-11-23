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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 15), GridItem(.flexible())], spacing: 15) {
                ForEach(BookTemplate.allCases) { option in
                    card(option)
                }
            }
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
        let style = option.style
        let active = option == selected
        return Button { selected = option } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 1) {
                    let inset = option == .gallery ? 14.0 : 10.0
                    ZStack(alignment: .topLeading) {
                        Color(cgColor: EditorialStyle.color(style.paper))
                        VStack(alignment: .leading, spacing: 8) {
                            if style.rule {
                                Rectangle().fill(Color(cgColor: EditorialStyle.color(style.accent)))
                                    .frame(height: 0.65)
                            }
                            Text(book.title.isEmpty ? tr("Un viaggio", "A journey") : book.title)
                                .font(.custom(style.titleFont, size: 16))
                                .lineLimit(2)
                                .foregroundStyle(Color(cgColor: EditorialStyle.color(style.ink)))
                            if let caption = book.pages.lazy.compactMap(\.heading).first {
                                Text(caption)
                                    .font(.custom(style.bodyFont, size: 8))
                                    .foregroundStyle(Color(cgColor: EditorialStyle.color(style.ink)).opacity(0.8))
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, inset)
                        .padding(.top, option == .diary ? 24 : 15)
                    }
                    ZStack {
                        Color(cgColor: EditorialStyle.color(style.paper))
                        if let hero {
                            GeometryReader { proxy in
                                let g: CGFloat = option == .essential ? 0 : (option == .atlas ? 8 : 13)
                                Image(nsImage: hero)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: proxy.size.width - 2*g, height: proxy.size.height - 2*g)
                                    .clipped()
                                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            }
                        }
                    }
                }
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

    private func tr(_ italian: String, _ english: String) -> String { language == "it" ? italian : english }
}
