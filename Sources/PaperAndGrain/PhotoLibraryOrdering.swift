import Foundation

enum PhotoLibraryOrder: String, CaseIterable, Identifiable {
    case date, place, subject, usage

    var id: Self { self }
}

/// Groups the inspector's filtered results, preserving the original order for equal dates.
final class PhotoLibraryOrdering {
    struct Section: Identifiable {
        enum Key: Hashable {
            case day(Date), place(String), area(latitude: Int, longitude: Int), subject(String)
            case unused, used, unknown
        }

        let id: Key
        let photos: [BookPhoto]
    }

    private struct Query: Equatable {
        let photos: [BookPhoto]
        let order: PhotoLibraryOrder
        let locale: Locale
        let calendar: Calendar
        let places: [UUID: PhotoLocation]
        let used: Set<UUID>
    }

    private var previous: Query?
    private var sections: [Section] = []

    func groups(for photos: [BookPhoto], order: PhotoLibraryOrder, locale: Locale, calendar: Calendar = .current,
                places: [UUID: PhotoLocation] = [:], used: Set<UUID> = []) -> [Section] {
        let query = Query(photos: photos, order: order, locale: locale, calendar: calendar,
                          places: order == .place ? places : [:], used: order == .usage ? used : [])
        if query == previous { return sections }

        let chronological = photos.enumerated().sorted { lhs, rhs in
            switch (lhs.element.capturedAt, rhs.element.capturedAt) {
            case let (left?, right?) where left != right: left < right
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.offset < rhs.offset
            }
        }.map(\.element)

        let grouped = Dictionary(grouping: chronological) { photo in
            key(for: photo, query: query)
        }
        sections = grouped.map { Section(id: $0.key, photos: $0.value) }
            .sorted { precedes($0.id, $1.id, locale: locale) }
        previous = query
        return sections
    }

    private func key(for photo: BookPhoto, query: Query) -> Section.Key {
        switch query.order {
        case .date:
            return photo.capturedAt.map { .day(query.calendar.startOfDay(for: $0)) } ?? .unknown
        case .place:
            guard let place = photo.location ?? query.places[photo.id] else { return .unknown }
            if let name = place.name, !name.isEmpty { return .place(name) }
            if let lat = place.latitude, let lon = place.longitude,
               (-90...90).contains(lat), (-180...180).contains(lon) {
                // Round into approximate GPS areas without looking up locations on a server.
                return .area(latitude: Int((lat * 20).rounded()), longitude: Int((lon * 20).rounded()))
            }
            return .unknown
        case .subject:
            let topics = photo.analysis?.concepts ?? []
            let topic = topics.first { $0 != "outdoors" && $0 != "sand" } ?? topics.first
            return topic.map(Section.Key.subject) ?? .unknown
        case .usage:
            return query.used.contains(photo.id) ? .used : .unused
        }
    }

    private func precedes(_ lhs: Section.Key, _ rhs: Section.Key, locale: Locale) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, _): false
        case (_, .unknown): true
        case let (.day(left), .day(right)): left < right
        case let (.place(left), .place(right)): alphabetic(left, right, locale: locale)
        case let (.subject(left), .subject(right)):
            alphabetic(PhotoAnalyzer.displayName(for: left, language: locale.identifier),
                       PhotoAnalyzer.displayName(for: right, language: locale.identifier), locale: locale)
        case (.place, .area): true
        case let (.area(leftLat, leftLon), .area(rightLat, rightLon)):
            leftLat == rightLat ? leftLon < rightLon : leftLat > rightLat
        case (.unused, .used): true
        default: false
        }
    }

    private func alphabetic(_ lhs: String, _ rhs: String, locale: Locale) -> Bool {
        let order = lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: locale)
        return order == .orderedSame ? lhs < rhs : order == .orderedAscending
    }
}
