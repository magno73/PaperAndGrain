import Foundation

/// Indexes only the photos that have a visible frame on a page or cover.
final class PhotoUsageIndex {
    enum Location: Equatable {
        case page(ClosedRange<Int>), frontCover, backCover
    }

    private var snapshot: Book?
    private var locations: [UUID: [Location]] = [:]

    func locations(in book: Book) -> [UUID: [Location]] {
        if snapshot == book { return locations }

        let photos = Dictionary(book.photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var updated: [UUID: [Location]] = [:]
        var number = 1
        for page in book.pages {
            let last = number + (page.effectiveLayout == .fullSpread ? 1 : 0)
            if !page.photoIDs.isEmpty {
                let composition = PageComposition(page: page, book: book, photoForID: { photos[$0] })
                var indexed = Set<UUID>()
                for photo in composition.photos where !photo.frame.intersection(composition.bounds).isEmpty {
                    if indexed.insert(photo.id).inserted {
                        updated[photo.id, default: []].append(.page(number...last))
                    }
                }
            }
            number = last + 1
        }
        for (id, location, front) in [
            (book.cover?.frontPhotoID, Location.frontCover, true),
            (book.cover?.backPhotoID, Location.backCover, false),
        ] {
            guard let id, photos[id] != nil else { continue }
            let face = BookCoverGeometry(book: book, front: front)
            if !face.photoFrame.intersection(face.bounds).isEmpty {
                updated[id, default: []].append(location)
            }
        }

        snapshot = book
        locations = updated
        return updated
    }
}
