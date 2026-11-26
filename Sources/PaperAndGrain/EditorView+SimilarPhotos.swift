import SwiftUI

/// What the grouping reads from a photo, before it is parsed.
struct SimilarKeyItem: Hashable {
    let id: UUID
    let hash: String?
    let date: Date?
}

/// A group of similar photos opened in the compare sheet.
struct SimilarComparison: Identifiable, Equatable {
    let id = UUID()
    let members: [UUID]
    var page = 0
}

/// The Photo Library's **Stack Similar** mode and the compare sheet.
extension EditorView {
    /// Recomputes the groups off the main thread when a hash or a date changes.
    func refreshSimilarGroups() async {
        guard stacksSimilar else {
            if !similarGroups.isEmpty { similarGroups = [] }
            return
        }
        let photos = book.photos
        let groups = await Task.detached(priority: .utility) {
            SimilarPhotos.groups(SimilarPhotos.entries(photos))
        }.value
        if !Task.isCancelled, groups != similarGroups { similarGroups = groups }
    }

    /// What the grouping reads, unparsed, so `.task(id:)` runs again only when a hash or a date changes.
    var similarKey: [SimilarKeyItem] {
        guard stacksSimilar else { return [] }
        return book.photos.map {
            SimilarKeyItem(id: $0.id, hash: $0.analysis?.visual?.perceptualHash, date: $0.capturedAt)
        }
    }

    func stackIsOpen(_ stack: SimilarPhotos.Stack) -> Bool {
        stack.members.first.map { expandedStacks.contains($0) } ?? false
    }

    func toggleStack(_ stack: SimilarPhotos.Stack) {
        guard let key = stack.members.first else { return }
        stackBadgeClickedAt = Date()
        if expandedStacks.contains(key) { expandedStacks.remove(key) } else { expandedStacks.insert(key) }
    }

    /// What VoiceOver says about a tile: its details, and its place in a stack.
    func stackAccessibilityValue(_ details: String, stack: SimilarPhotos.Stack?, behind: Bool) -> String {
        var parts = [details]
        if let stack { parts.append(tr("%lld similar photos", stack.members.count)) }
        if behind { parts.append(tr("In a stack of similar photos")) }
        return parts.joined(separator: " · ")
    }

    /// The count badge on a stack's thumbnail: it opens and closes the group in place.
    func stackBadge(_ stack: SimilarPhotos.Stack) -> some View {
        let open = stackIsOpen(stack)
        return Button { toggleStack(stack) } label: {
            Label("\(stack.members.count)", systemImage: open ? "chevron.left.2" : "square.on.square")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.80), in: Capsule())
                .padding(3)
        }
        .buttonStyle(.plain)
        .help(open ? tr("Hide the similar photos") : tr("Show the similar photos"))
        // The tile is one accessibility element; its action and value carry the badge.
        .accessibilityHidden(true)
    }

    func compare(_ members: [UUID]) {
        comparison = SimilarComparison(members: members)
    }

    // MARK: Use This One

    /// Replaces the members of the group that are near-duplicates of `chosen` itself with `chosen`, wherever
    /// they are placed (pages and the two cover faces), keeping frames, crops and layers. One undo step: all
    /// pages change in one `editPages` call and a cover face registers in the same undo group. No photo is
    /// deleted from the book.
    func useThisOne(_ chosen: UUID, among members: [UUID]) {
        let others = SimilarPhotos.replaceable(by: chosen, in: members, entries: SimilarPhotos.entries(book.photos))
        defer { comparison = nil }
        guard !others.isEmpty else { return }
        let name = tr("Use This One")
        editPages(name) { pages in
            for index in pages.indices {
                for other in others { pages[index].substitutePhoto(other, with: chosen) }
            }
        }
        // The caption belongs to the photo: carry it over when the chosen one has none. Same undo step.
        if case let .copy(caption) = captionCarry(chosen, replacing: others), let index = photoIndex(chosen) {
            let previous = book.photos[index].caption
            book.photos[index].caption = caption
            if let undoManager {
                undoTarget.registerPhotoValue(undoManager, binding: $book, bookID: book.id, photoID: chosen,
                                              key: \.caption, previous: previous, name: name)
            }
        }
        for side in [CoverSide.front, .back] {
            guard let current = coverPhotoID(side), others.contains(current) else { continue }
            let key: WritableKeyPath<BookCover, UUID?> = side == .front ? \.frontPhotoID : \.backPhotoID
            let before = CoverImage(id: current, placement: coverPhotoPlacement(side))
            changeCover { $0[keyPath: key] = chosen }
            if let undoManager {
                undoTarget.registerCoverImage(undoManager, binding: $book, bookID: book.id, idKey: key,
                                              placementKey: coverPlacementKey(side), previous: before, name: name)
            }
        }
    }

    func captionCarry(_ chosen: UUID, replacing others: [UUID]) -> SimilarPhotos.CaptionCarry {
        guard let photo = indexedPhoto(chosen) else { return .none }
        return SimilarPhotos.captionCarry(chosen: photo, replaced: others.compactMap(indexedPhoto))
    }

    /// Where `chosen` would replace others, for the sheet to say before the click, and what happens to captions.
    func useThisOneEffect(_ chosen: UUID, among members: [UUID], locations: [UUID: [PhotoUsageIndex.Location]]) -> String {
        let others = SimilarPhotos.replaceable(by: chosen, in: members, entries: SimilarPhotos.entries(book.photos))
        if others.isEmpty { return tr("No other photo is close enough to this one to be replaced.") }
        var seen = Set<String>()
        let places = others.flatMap { locations[$0] ?? [] }.map(usageDescription).filter { seen.insert($0).inserted }
        let effect = places.isEmpty ? tr("The similar photos are not placed, so no page changes.")
            : tr("Replaces the similar photos on: %@", places.joined(separator: ", "))
        switch captionCarry(chosen, replacing: others) {
        case .none: return effect
        case let .copy(caption): return effect + " " + tr("Takes the caption “%@”.", caption)
        case .keepsOwn: return effect + " " + tr("Keeps its own caption; a replaced photo has a different one.")
        }
    }

    // MARK: Compare sheet

    func comparisonSheet(_ current: SimilarComparison) -> some View {
        let perPage = 4
        let pages = max(1, (current.members.count + perPage - 1) / perPage)
        let page = min(current.page, pages - 1)
        let visible = Array(current.members.dropFirst(page * perPage).prefix(perPage))
        let locations = photoUsageIndex.locations(in: book)
        let dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: language))
        return VStack(alignment: .leading, spacing: 14) {
            Text(tr("Compare Similar Photos")).font(.headline)
            HStack(alignment: .top, spacing: 14) {
                ForEach(visible, id: \.self) { id in
                    if let photo = indexedPhoto(id) {
                        VStack(alignment: .leading, spacing: 6) {
                            preview(photo, small: false, fills: false, proof: false)
                                .frame(width: 230, height: 190)
                                .background(pine.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel(photo.name)
                            Text(photo.name).font(.callout.weight(.semibold)).lineLimit(1)
                            Text("\(photo.pixelWidth) × \(photo.pixelHeight)").font(.caption).foregroundStyle(muted)
                            Text(photo.capturedAt.map { $0.formatted(dateStyle) } ?? tr("No Date"))
                                .font(.caption).foregroundStyle(muted)
                            Text((locations[id] ?? []).isEmpty ? tr("Not on a page")
                                 : (locations[id] ?? []).map(usageDescription).joined(separator: ", "))
                                .font(.caption).foregroundStyle(muted).lineLimit(2)
                            Button(tr("Use This One")) { useThisOne(id, among: current.members) }
                                .help(tr("Replace the similar photos of this group with this one wherever they are placed"))
                            Text(useThisOneEffect(id, among: current.members, locations: locations))
                                .font(.caption2).foregroundStyle(muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 230, alignment: .leading)
                    }
                }
            }
            HStack {
                if pages > 1 {
                    Button(tr("Previous"), systemImage: "chevron.left") { comparison?.page = max(0, page - 1) }
                        .disabled(page == 0)
                        .help(tr("Show the previous photos of the group"))
                    Text(tr("%1$lld of %2$lld", page + 1, pages)).font(.caption).foregroundStyle(muted).monospacedDigit()
                    Button(tr("Next"), systemImage: "chevron.right") { comparison?.page = min(pages - 1, page + 1) }
                        .disabled(page >= pages - 1)
                        .help(tr("Show the next photos of the group"))
                }
                Spacer()
                Button(tr("Done")) { comparison = nil }
                    .keyboardShortcut(.defaultAction)
                    .help(tr("Close the comparison"))
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }
}
