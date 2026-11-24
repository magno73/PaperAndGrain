import Foundation

/// Keeps library metadata and the current filter result across inspector redraws.
final class InspectorPhotoLibraryCache {
    struct Concept: Identifiable {
        let id: String
        let name: String
        let count: Int
    }

    private struct Filter: Equatable {
        let search: String
        let concept: String?
        let locale: Locale
    }

    private var photos: [BookPhoto] = []
    private var language = ""
    private var concepts: [Concept] = []
    private var conceptNames: [String: String] = [:]
    private var filter: Filter?
    private var matches: [BookPhoto] = []

    func results(photos: [BookPhoto], language: String, search: String, concept: String?)
        -> (concepts: [Concept], photos: [BookPhoto]) {
        if self.photos != photos || self.language != language {
            self.photos = photos
            self.language = language
            var counts: [String: Int] = [:]
            for photo in photos {
                for item in Set(photo.analysis?.concepts ?? []) {
                    counts[item, default: 0] += 1
                }
            }
            concepts = counts.map { id, count in
                Concept(id: id, name: PhotoAnalyzer.displayName(for: id, language: language), count: count)
            }.sorted { left, right in
                left.count == right.count ? left.name < right.name : left.count > right.count
            }
            conceptNames = Dictionary(uniqueKeysWithValues: concepts.map { ($0.id, $0.name) })
            filter = nil
            matches = []
        }

        guard concept != nil || !search.isEmpty else { return (concepts, photos) }
        let query = Filter(search: search, concept: concept, locale: .current)
        if filter != query {
            filter = query
            matches = photos.filter { photo in
                let items = photo.analysis?.concepts ?? []
                if let concept, !items.contains(concept) { return false }
                return search.isEmpty || photo.name.localizedStandardContains(search)
                    || items.contains { (conceptNames[$0] ?? $0).localizedStandardContains(search) }
                    || photo.analysis?.labels.contains { $0.localizedStandardContains(search) } == true
                    || photo.analysis?.detections?.contains { $0.label.localizedStandardContains(search) } == true
                    || photo.analysis?.recognizedText?.contains { $0.text.localizedStandardContains(search) } == true
            }
        }
        return (concepts, matches)
    }
}
