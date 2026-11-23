import AppKit
import CoreText
import SwiftUI

struct EditorialTypographyControls: View {
    @Binding var style: EditorialTextStyle?
    let inherited: EditorialTextStyle
    let language: String
    var updatesSizeWhileTyping = false

    @State private var sizeDraft: String?
    @State private var sizeBeforeEditing: Double?
    @State private var showingFonts = false
    @State private var fontSearch = ""
    @State private var fonts: [FontChoice]?
    @FocusState private var editingSize: Bool
    @FocusState private var searchingFonts: Bool

    private let pine = Color(red: 0.14, green: 0.31, blue: 0.23)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            fontControl
            HStack(spacing: 5) {
                sizeControl
                Spacer(minLength: 2)
                alignmentControl
                resetControl
            }
        }
        .controlSize(.small)
    }

    private var fontControl: some View {
        let label = tr("Carattere", "Font")
        let name = displayName(for: style?.fontName ?? inherited.fontName)
        return Button {
            fontSearch = ""
            showingFonts.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(name)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .accessibilityValue(name)
        .help(name)
        .popover(isPresented: $showingFonts, arrowEdge: .bottom) { fontPicker }
    }

    private var sizeControl: some View {
        let label = tr("Dimensione carattere", "Font Size")
        let reference = tr("Da 6 a 120 punti. Cancella il valore per usare la dimensione ereditata.",
                           "6 to 120 points. Clear the value to use the inherited size.")
        return HStack(spacing: 3) {
            TextField(label, text: Binding(get: { sizeDraft ?? formattedSize }, set: { draft in
                sizeDraft = draft
                if updatesSizeWhileTyping { applySize(draft) }
            }))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($editingSize)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 46)
                .onSubmit {
                    commitSize()
                    editingSize = false
                }
                .onChange(of: editingSize) { wasEditing, isEditing in
                    if isEditing { sizeBeforeEditing = style?.pointSize }
                    if wasEditing && !isEditing { commitSize() }
                }
                .onExitCommand {
                    if updatesSizeWhileTyping { set(\.pointSize, to: sizeBeforeEditing) }
                    sizeDraft = nil
                    editingSize = false
                }
                .help(reference)
                .accessibilityHint(reference)
            Text("pt")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var alignmentControl: some View {
        let resolved = style?.alignment ?? inherited.alignment ?? .left
        return HStack(spacing: 0) {
            ForEach(EditorialAlignment.allCases) { alignment in
                let info = alignmentInfo(alignment)
                let active = alignment == resolved
                Button { set(\.alignment, to: alignment) } label: {
                    Image(systemName: info.icon)
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? pine : Color.secondary)
                        .frame(width: 23, height: 22)
                        .background(active ? pine.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(info.label)
                .accessibilityAddTraits(active ? .isSelected : [])
                .help(info.label)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Allineamento", "Alignment"))
        .contextMenu {
            Button(tr("Usa allineamento ereditato", "Use Inherited Alignment")) { set(\.alignment, to: nil) }
                .disabled(style?.alignment == nil)
        }
    }

    private var resetControl: some View {
        let label = tr("Ripristina impostazioni ereditate", "Reset to Inherited Settings")
        return Button {
            sizeDraft = nil
            editingSize = false
            style = nil
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11))
                .frame(width: 23, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(style == nil || style == EditorialTextStyle())
        .accessibilityLabel(label)
        .help(label)
    }

    private var fontPicker: some View {
        let search = fontSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = fonts.map { list in search.isEmpty ? list : list.filter { $0.matches(search) } }
        return VStack(alignment: .leading, spacing: 8) {
            TextField(tr("Cerca carattere", "Search Fonts"), text: $fontSearch)
                .textFieldStyle(.roundedBorder)
                .focused($searchingFonts)
                .onSubmit {
                    if let options, options.count == 1 { chooseFont(options[0].postScriptName) }
                }
            fontRow(tr("Usa carattere ereditato", "Use Inherited Font"),
                    detail: displayName(for: inherited.fontName), postScriptName: nil)
            Divider()
            if let options {
                if options.isEmpty {
                    Text(tr("Nessun carattere trovato", "No fonts found"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(options) { font in
                                fontRow(font.displayName, postScriptName: font.postScriptName)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(tr("Caricamento caratteri", "Loading Fonts"))
            }
        }
        .padding(10)
        .frame(width: 300, height: 295)
        .task {
            searchingFonts = true
            if fonts == nil {
                let catalog = await FontChoice.catalog.value
                if !Task.isCancelled { fonts = catalog }
            }
        }
    }

    private func fontRow(_ name: String, detail: String? = nil, postScriptName: String?) -> some View {
        let active = style?.fontName == postScriptName
        return Button { chooseFont(postScriptName) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                if let postScriptName {
                    Text("Aa")
                        .font(.custom(postScriptName, size: 14))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(pine)
                    .opacity(active ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(active ? pine.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(detail ?? "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var effectiveSize: Double {
        style?.normalizedSize ?? inherited.normalizedSize ?? 12
    }

    private var formattedSize: String {
        effectiveSize.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
            .locale(Locale(identifier: language)))
    }

    private func commitSize() {
        guard let draft = sizeDraft else { return }
        sizeDraft = nil
        applySize(draft)
    }

    private func applySize(_ draft: String) {
        let entry = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.isEmpty {
            set(\.pointSize, to: nil)
        } else if entry != formattedSize {
            let separator = Locale(identifier: language).decimalSeparator ?? "."
            guard let number = Double(entry.replacingOccurrences(of: separator, with: ".")), number.isFinite else { return }
            let range = EditorialTextStyle.pointSizeRange
            let size = min(range.upperBound, max(range.lowerBound, number))
            if style?.pointSize != nil || size != effectiveSize { set(\.pointSize, to: size) }
        }
    }

    private func chooseFont(_ name: String?) {
        showingFonts = false
        set(\.fontName, to: name)
    }

    private func set<Value>(_ key: WritableKeyPath<EditorialTextStyle, Value?>, to value: Value?) {
        var updated = style ?? EditorialTextStyle()
        updated[keyPath: key] = value
        let next: EditorialTextStyle? = updated == EditorialTextStyle() ? nil : updated
        if next != style { style = next }
    }

    private func displayName(for fontName: String?) -> String {
        guard let fontName else { return tr("Carattere di sistema", "System Font") }
        return NSFont(name: fontName, size: 12)?.displayName ?? fontName
    }

    private func alignmentInfo(_ alignment: EditorialAlignment) -> (icon: String, label: String) {
        switch alignment {
        case .left: ("text.alignleft", tr("Allinea a sinistra", "Align Left"))
        case .center: ("text.aligncenter", tr("Centra", "Center"))
        case .right: ("text.alignright", tr("Allinea a destra", "Align Right"))
        case .justified: ("text.justify", tr("Giustifica", "Justify"))
        }
    }

    private func tr(_ italian: String, _ english: String) -> String {
        language.hasPrefix("it") ? italian : english
    }
}

private struct FontChoice: Identifiable, Sendable {
    let postScriptName: String
    let displayName: String
    var id: String { postScriptName }

    func matches(_ search: String) -> Bool {
        displayName.localizedStandardContains(search) || postScriptName.localizedStandardContains(search)
    }

    /// Core Text enumeration runs once, starting only when the font picker opens.
    static let catalog = Task.detached(priority: .userInitiated) {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        var seen: Set<String> = []
        return descriptors.compactMap { descriptor -> Self? in
            guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                  seen.insert(name).inserted else { return nil }
            let title = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String ?? name
            return Self(postScriptName: name, displayName: title)
        }.sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.postScriptName < $1.postScriptName : order == .orderedAscending
        }
    }
}
