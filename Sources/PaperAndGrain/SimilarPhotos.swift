import Foundation

/// Groups near-duplicate photos, from the perceptual hash that the analysis stores. Pure and quick: the
/// Photo Library runs it off the main thread to stack similar photos.
enum SimilarPhotos {
    /// Share of differing hash bits up to which two photos are near-duplicates. Chosen on generated pictures
    /// (see docs/architecture.md): 8 of 64 bits keeps different pictures apart with a margin of 3 bits.
    static let nearDuplicate = 0.125
    /// The same, for two photos taken within `closeSeconds` of each other (a burst, a re-framed shot).
    static let closeInTime = 0.16
    static let closeSeconds = 120.0

    private static let nearBits = Int((nearDuplicate * 64).rounded(.down))
    private static let closeBits = Int((closeInTime * 64).rounded(.down))

    /// What the grouping reads from a photo. A photo without a hash has no entry.
    struct Entry: Hashable, Sendable {
        let id: UUID
        let hash: UInt64
        /// Seconds since the reference date, when the photo has a capture date.
        let time: Double?
    }

    static func entries(_ photos: [BookPhoto]) -> [Entry] {
        photos.compactMap { photo in
            guard let text = photo.analysis?.visual?.perceptualHash, text.count == 16,
                  let hash = UInt64(text, radix: 16) else { return nil }
            return Entry(id: photo.id, hash: hash, time: photo.capturedAt?.timeIntervalSinceReferenceDate)
        }
    }

    /// Connected sets of near-duplicates, two or more photos each. Members are ordered by capture date
    /// (undated last) then id; the groups are ordered by their first member. The result does not depend on
    /// the order of `entries`.
    static func groups(_ entries: [Entry]) -> [[UUID]] {
        let sorted = entries.sorted(by: before)
        let count = sorted.count
        var parent = Array(0..<count)
        func root(_ index: Int) -> Int {
            var node = index
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }
        let hashes = sorted.map(\.hash)
        let times = sorted.map { $0.time ?? .nan }
        let near = nearBits, close = closeBits, window = closeSeconds
        // The pairwise pass is the cost; raw buffers keep it fast in a debug build too.
        hashes.withUnsafeBufferPointer { h in
            times.withUnsafeBufferPointer { t in
                for i in 0..<count {
                    let hash = h[i], time = t[i]
                    for j in (i + 1)..<max(count, i + 1) {
                        let bits = (hash ^ h[j]).nonzeroBitCount
                        guard bits <= close, bits <= near || abs(time - t[j]) <= window else { continue }
                        let a = root(i), b = root(j)
                        if a != b { parent[max(a, b)] = min(a, b) }
                    }
                }
            }
        }
        var members: [Int: [UUID]] = [:]
        var order: [Int] = []
        for index in 0..<count {
            let key = root(index)
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(sorted[index].id)
        }
        return order.compactMap { members[$0] }.filter { $0.count > 1 }
    }

    /// True when two photos are near-duplicates of each other directly (not through a chain of others).
    static func isSimilar(_ a: Entry, _ b: Entry) -> Bool {
        let bits = (a.hash ^ b.hash).nonzeroBitCount
        guard bits <= closeBits else { return false }
        if bits <= nearBits { return true }
        guard let x = a.time, let y = b.time else { return false }
        return abs(x - y) <= closeSeconds
    }

    /// The members of `group` that **Use This One** may replace with `chosen`: only those that are
    /// near-duplicates of `chosen` itself. A group is a connected set, so a chain of slowly changing shots can
    /// hold photos that are not alike; those stay as they are.
    static func replaceable(by chosen: UUID, in group: [UUID], entries: [Entry]) -> [UUID] {
        guard let target = entries.first(where: { $0.id == chosen }) else { return [] }
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return group.filter { id in
            id != chosen && byID[id].map { isSimilar(target, $0) } == true
        }
    }

    private static func before(_ a: Entry, _ b: Entry) -> Bool {
        switch (a.time, b.time) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.id.uuidString < b.id.uuidString
        }
    }

    /// One group as the Photo Library shows it: a photo on top and the others behind it.
    struct Stack: Equatable, Sendable {
        /// The photo that stands for the group.
        let shown: UUID
        /// All members, in the group's order, the shown one included.
        let members: [UUID]
    }

    /// The photo shown for a group: the one already placed in the book, otherwise the one with the most
    /// detail (sharpness), otherwise the earliest. A tie goes to the earlier member.
    static func shownPhoto(in group: [UUID], photo: (UUID) -> BookPhoto?, placed: Set<UUID>) -> UUID {
        if let onPage = group.first(where: { placed.contains($0) }) { return onPage }
        var best = group[0]
        var bestDetail = photo(best)?.analysis?.visual?.sharpness ?? -1
        for id in group.dropFirst() {
            let detail = photo(id)?.analysis?.visual?.sharpness ?? -1
            if detail > bestDetail {
                best = id
                bestDetail = detail
            }
        }
        return best
    }

    /// The stacks of the photos in `visible` (what the library's filter and search let through): a group
    /// keeps only its visible members, and stacks when two or more remain, with the best of them shown.
    static func stacks(_ groups: [[UUID]], visible: Set<UUID>, photo: (UUID) -> BookPhoto?,
                       placed: Set<UUID>) -> [Stack] {
        groups.compactMap { group in
            let members = group.filter { visible.contains($0) }
            guard members.count > 1 else { return nil }
            return Stack(shown: shownPhoto(in: members, photo: photo, placed: placed), members: members)
        }
    }
}

/// The stacks of a Photo Library view: which photo stands for each group and which are behind it.
struct SimilarStackIndex: Sendable {
    /// Stacks by the photo they show.
    var byShown: [UUID: SimilarPhotos.Stack] = [:]
    /// Photos that sit behind another one.
    var behind: Set<UUID> = []

    init(_ stacks: [SimilarPhotos.Stack] = []) {
        for stack in stacks {
            byShown[stack.shown] = stack
            for member in stack.members where member != stack.shown { behind.insert(member) }
        }
    }

    /// The photos of a library section with the stacks the author opened laid out after the photo they
    /// belong to. Photos behind a stack are left out unless it is open. `photo(id)` resolves a member.
    func laidOut(_ photos: [BookPhoto], opened: Set<UUID>, photo: (UUID) -> BookPhoto?)
        -> [(photo: BookPhoto, behind: Bool)] {
        var result: [(BookPhoto, Bool)] = []
        for item in photos where !behind.contains(item.id) {
            result.append((item, false))
            if let stack = byShown[item.id], let key = stack.members.first, opened.contains(key) {
                for member in stack.members where member != stack.shown {
                    if let other = photo(member) { result.append((other, true)) }
                }
            }
        }
        return result
    }
}

extension BookPage {
    /// Puts `chosen` where `other` is on this page, keeping the frame, crop and layer. When the page already
    /// has `chosen`, `other` is only removed. Returns true when the page changed.
    @discardableResult
    mutating func substitutePhoto(_ other: UUID, with chosen: UUID) -> Bool {
        guard other != chosen, let index = photoIDs.firstIndex(of: other) else { return false }
        var placements = photoPlacements ?? [:]
        if photoIDs.contains(chosen) {
            photoIDs.remove(at: index)
            layerOrder?.removeAll { $0 == .photo(other) }
        } else {
            photoIDs[index] = chosen
            if let placement = placements[other] { placements[chosen] = placement }
            layerOrder = layerOrder?.map { $0 == .photo(other) ? .photo(chosen) : $0 }
        }
        placements.removeValue(forKey: other)
        photoPlacements = placements.isEmpty ? nil : placements
        return true
    }
}
