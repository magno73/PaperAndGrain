import AppKit
import CoreText
import SwiftUI

struct EditorialFontBrowser: View, Localizing {
    let selected: String?
    let inherited: String?
    let sampleText: String
    let language: String
    let onSelect: (String?) -> Void

    @AppStorage("editorial.fontFavorites") private var favoriteNames = ""
    @AppStorage("editorial.recentFonts") private var recentNames = ""
    @State private var catalog: [Family]?
    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var familyID: String?
    @State private var faceID: String?
    @FocusState private var searchFocused: Bool

    private let pine = Theme.accent
    private let paper = Theme.field

    private enum Scope: CaseIterable {
        case all, favorites, recent
    }

    var body: some View {
        let options = matchingFamilies
        let family = familyID.flatMap { id in options.first { $0.id == id } } ?? options.first
        let face = family?.faces.first { $0.id == faceID } ?? family?.preferredFace
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                searchField(options, family: family, face: face)
                Picker(tr("Font Collection"), selection: $scope) {
                    Text(tr("All", key: "fonts.all")).tag(Scope.all)
                    Text(tr("Favorites")).tag(Scope.favorites)
                    Text(tr("Recent")).tag(Scope.recent)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            listing(options, family: family, face: face)
            specimen(family: family, face: face)
            HStack(spacing: 8) {
                let label = tr("Use Inherited Font")
                let name = Self.displayName(inherited, language: language)
                Button(label) { onSelect(nil) }
                    .buttonStyle(.link)
                    .disabled(selected == nil)
                    .accessibilityValue(name)
                    .help(name)
                Spacer(minLength: 3)
                Button(tr("Apply Font")) { if let face { apply(face) } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(face == nil)
            }
        }
        .padding(12)
        .frame(width: 412)
        .controlSize(.small)
        .tint(pine)
        .task {
            searchFocused = true
            let loaded = await Family.catalog.value
            guard !Task.isCancelled else { return }
            catalog = loaded
            let name = selected ?? inherited
            familyID = loaded.first { $0.faces.contains { $0.id == name } }?.id
            faceID = name
        }
    }

    private func searchField(_ options: [Family], family: Family?, face: Face?) -> some View {
        let label = tr("Search Families or Styles")
        let hint = tr("Use the arrow keys to choose a family, Option with the arrow keys to choose a style, and Return to apply.")
        return HStack(spacing: 5) {
            Button { searchFocused = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel(label)
            TextField(label, text: $query)
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityHint(hint)
                .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                    let direction = press.key == .upArrow ? -1 : 1
                    if press.modifiers.contains(.option), let family {
                        if let next = neighbor(in: family.faces, around: face?.id, direction: direction) {
                            familyID = family.id
                            faceID = next.id
                        }
                    } else if let next = neighbor(in: options, around: family?.id, direction: direction) {
                        selectFamily(next)
                    }
                    return .handled
                }
                .onSubmit { if let face { apply(face) } }
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 23)
        .background(paper, in: RoundedRectangle(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(pine.opacity(searchFocused ? 0.65 : 0.2)) }
    }

    private func listing(_ options: [Family], family: Family?, face: Face?) -> some View {
        VStack(spacing: 0) {
            if catalog == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(tr("Loading Fonts"))
            } else if let family {
                HStack(spacing: 0) {
                    optionList(tr("Family"), options: options, selectedID: family.id) { option in
                        row(option.id, active: option.id == family.id) { selectFamily(option) }
                    }
                    .frame(width: 179)
                    Divider()
                    optionList(tr("Style"), options: family.faces, selectedID: face?.id) { option in
                        row(option.style, active: option.id == face?.id, accessory: option.id == selected ? "checkmark" : nil) {
                            familyID = family.id
                            faceID = option.id
                        }
                        .help(option.name)
                        .accessibilityValue(option.id == selected ? tr("Applied") : "")
                    }
                }
            } else {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 218)
        .background(paper, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(pine.opacity(0.15)) }
    }

    private func optionList<Option: Identifiable, Row: View>(_ title: String, options: [Option],
        selectedID: Option.ID?, @ViewBuilder row: @escaping (Option) -> Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(options) { option in row(option).id(option.id) }
                    }
                    .padding(3)
                }
                .onChange(of: selectedID, initial: true) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func row(_ title: String, active: Bool, accessory: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                Spacer(minLength: 2)
                if let accessory {
                    Image(systemName: accessory)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(pine)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 23)
            .background(active ? pine.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func specimen(family: Family?, face: Face?) -> some View {
        let name = face?.id ?? selected ?? inherited
        let sample = sampleText.prefix(140).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let description = Self.displayName(name, language: language)
        let previewFont = name.map { Font.custom($0, size: 23) } ?? .system(size: 23, design: .serif)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(family.flatMap { family in face.map { family.id + " · " + $0.style } } ?? description)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(sample.isEmpty ? tr("The journey continues") : sample)
                    .font(previewFont)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let face {
                let favorite = favorites.contains(face.id)
                let label = favorite ? tr("Remove from Favorites")
                    : tr("Add to Favorites")
                Button {
                    var updated = favorites
                    if favorite { updated.remove(face.id) } else { updated.insert(face.id) }
                    favoriteNames = updated.sorted().joined(separator: "\n")
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(pine)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .help(label)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(height: 84, alignment: .topLeading)
        .background(pine.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Font Preview"))
    }

    private var matchingFamilies: [Family] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let favorites = favorites
        let recent = recentNames.split(separator: "\n").map(String.init)
        let recentRanks = Dictionary(zip(recent, recent.indices), uniquingKeysWith: min)
        let matches = (catalog ?? []).compactMap { family -> Family? in
            let faces = family.faces.filter { face in
                switch scope {
                case .all: break
                case .favorites: if !favorites.contains(face.id) { return false }
                case .recent: if recentRanks[face.id] == nil { return false }
                }
                return terms.allSatisfy { term in
                    [family.id, face.id, face.style, face.name].contains { $0.localizedStandardContains(term) }
                }
            }
            return faces.isEmpty ? nil : Family(id: family.id, faces: faces)
        }
        guard scope == .recent else { return matches }
        func rank(_ family: Family) -> Int {
            family.faces.compactMap { recentRanks[$0.id] }.min() ?? Int.max
        }
        return matches.sorted { rank($0) < rank($1) }
    }

    private var favorites: Set<String> { Set(favoriteNames.split(separator: "\n").map(String.init)) }

    private var emptyMessage: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tr("No Fonts Found")
        }
        switch scope {
        case .all: return tr("No Fonts Available")
        case .favorites: return tr("No Favorite Fonts")
        case .recent: return tr("No Recent Fonts")
        }
    }

    private func selectFamily(_ family: Family) {
        familyID = family.id
        faceID = family.faces.first { $0.id == selected }?.id ?? family.preferredFace?.id
    }

    private func neighbor<Item: Identifiable>(in items: [Item], around id: Item.ID?, direction: Int) -> Item? {
        guard !items.isEmpty else { return nil }
        let current = items.firstIndex { $0.id == id } ?? 0
        return items[min(items.count - 1, max(0, current + direction))]
    }

    private func apply(_ face: Face) {
        let previous = recentNames.split(separator: "\n").map(String.init).filter { $0 != face.id }
        recentNames = ([face.id] + previous).prefix(8).joined(separator: "\n")
        onSelect(face.id)
    }

    static func displayName(_ fontName: String?, language: String) -> String {
        guard let fontName else { return L10n.string("System Font", language: language) }
        return NSFont(name: fontName, size: 12)?.displayName ?? fontName
    }

    private struct Face: Identifiable, Sendable {
        let id: String
        let name: String
        let style: String
    }

    private struct Family: Identifiable, Sendable {
        let id: String
        let faces: [Face]

        var preferredFace: Face? {
            let normal = ["regular", "roman", "normal", "book", "medium"]
            return normal.lazy.compactMap { style in faces.first { $0.style.lowercased() == style } }.first
                ?? faces.first
        }

        /// Core Text enumeration starts off the main thread on first opening.
        static let catalog = Task.detached(priority: .userInitiated) {
            let collection = CTFontCollectionCreateFromAvailableFonts(nil)
            let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
            var seen: Set<String> = []
            var groups: [String: [Face]] = [:]
            for descriptor in descriptors {
                guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                      seen.insert(name).inserted else { continue }
                let display = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String ?? name
                let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String ?? display
                let style = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? display
                groups[family, default: []].append(Face(id: name, name: display, style: style))
            }
            return groups.map { family, faces in
                Family(id: family, faces: faces.sorted { left, right in
                    let order = left.style.localizedStandardCompare(right.style)
                    return order == .orderedSame ? left.id < right.id : order == .orderedAscending
                })
            }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        }
    }
}
