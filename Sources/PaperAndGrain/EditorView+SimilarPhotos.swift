import SwiftUI

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
        let entries = SimilarPhotos.entries(book.photos)
        let groups = await Task.detached(priority: .utility) { SimilarPhotos.groups(entries) }.value
        if !Task.isCancelled, groups != similarGroups { similarGroups = groups }
    }

    /// What the grouping reads, so `.task(id:)` runs again only when it changes.
    var similarKey: [SimilarPhotos.Entry] { stacksSimilar ? SimilarPhotos.entries(book.photos) : [] }

    func toggleStack(_ stack: SimilarPhotos.Stack) {
        guard let key = stack.members.first else { return }
        if expandedStacks.contains(key) { expandedStacks.remove(key) } else { expandedStacks.insert(key) }
    }

    /// The count badge on a stack's thumbnail: it opens and closes the group in place.
    func stackBadge(_ stack: SimilarPhotos.Stack) -> some View {
        let open = stack.members.first.map { expandedStacks.contains($0) } ?? false
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
        .accessibilityLabel(tr("%lld similar photos", stack.members.count))
        .accessibilityHint(open ? tr("Hide the similar photos") : tr("Show the similar photos"))
    }

    func compare(_ members: [UUID]) {
        comparison = SimilarComparison(members: members)
    }

    // MARK: Use This One

    /// Replaces every other member of the group with `chosen` wherever it is placed (pages and the two cover
    /// faces), keeping frames, crops and layers. One undo step. No photo is deleted from the book.
    func useThisOne(_ chosen: UUID, among members: [UUID]) {
        let others = Set(members).subtracting([chosen])
        let previous = book.pages
        var changed = false
        for index in book.pages.indices {
            for other in others where book.pages[index].substitutePhoto(other, with: chosen) { changed = true }
        }
        if changed { registerUndo(previous, name: tr("Use This Photo")) }
        for side in [CoverSide.front, .back] {
            guard let current = coverPhotoID(side), others.contains(current) else { continue }
            let key: WritableKeyPath<BookCover, UUID?> = side == .front ? \.frontPhotoID : \.backPhotoID
            let placementKey = coverPlacementKey(side)
            let before = CoverImage(id: current, placement: coverPhotoPlacement(side))
            changeCover { $0[keyPath: key] = chosen }
            if let undoManager {
                undoTarget.registerCoverImage(undoManager, binding: $book, bookID: book.id, idKey: key,
                                              placementKey: placementKey, previous: before, name: tr("Use This Photo"))
            }
            changed = true
        }
        if changed { undoManager?.setActionName(tr("Use This Photo")) }
        comparison = nil
    }

    // MARK: Compare sheet

    func comparisonSheet(_ current: SimilarComparison) -> some View {
        let perPage = 4
        let pages = max(1, (current.members.count + perPage - 1) / perPage)
        let page = min(current.page, pages - 1)
        let visible = Array(current.members.dropFirst(page * perPage).prefix(perPage))
        let locations = photoUsageIndex.locations(in: book)
        let style = DateFormatter()
        style.locale = Locale(identifier: language)
        style.dateStyle = .medium
        style.timeStyle = .short
        return VStack(alignment: .leading, spacing: 14) {
            Text(tr("Compare Similar Photos")).font(.headline)
            HStack(alignment: .top, spacing: 14) {
                ForEach(visible, id: \.self) { id in
                    if let photo = indexedPhoto(id) {
                        VStack(alignment: .leading, spacing: 6) {
                            preview(photo, small: false, fills: false)
                                .frame(width: 230, height: 190)
                                .background(pine.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel(photo.name)
                            Text(photo.name).font(.callout.weight(.semibold)).lineLimit(1)
                            Text("\(photo.pixelWidth) × \(photo.pixelHeight)").font(.caption).foregroundStyle(muted)
                            Text(photo.capturedAt.map { style.string(from: $0) } ?? tr("No Date"))
                                .font(.caption).foregroundStyle(muted)
                            Text((locations[id] ?? []).isEmpty ? tr("Not on a page")
                                 : (locations[id] ?? []).map(usageDescription).joined(separator: ", "))
                                .font(.caption).foregroundStyle(muted).lineLimit(2)
                            Button(tr("Use This One")) { useThisOne(id, among: current.members) }
                                .help(tr("Replace the other photos of this group with this one wherever they are placed"))
                                .disabled(current.members.count < 2)
                        }
                        .frame(width: 230, alignment: .leading)
                    }
                }
            }
            HStack {
                if pages > 1 {
                    Button(tr("Previous"), systemImage: "chevron.left") { comparison?.page = max(0, page - 1) }
                        .disabled(page == 0)
                    Text(tr("%1$lld of %2$lld", page + 1, pages)).font(.caption).foregroundStyle(muted).monospacedDigit()
                    Button(tr("Next"), systemImage: "chevron.right") { comparison?.page = min(pages - 1, page + 1) }
                        .disabled(page >= pages - 1)
                }
                Spacer()
                Button(tr("Done")) { comparison = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }
}
