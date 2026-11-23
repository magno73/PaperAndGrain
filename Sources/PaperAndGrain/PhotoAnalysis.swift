import Foundation
import ImageIO
import Vision

struct PhotoAnalysis: Codable, Hashable, Sendable {
    var labels: [String]
    var concepts: [String]
    var revision: Int = 1
}

enum PhotoAnalyzer {
    private struct Topic {
        let key: String
        let english: String
        let italian: String
        let visual: [String]
        let aliases: [String]

        init(_ key: String, _ english: String, _ italian: String, _ visual: String, _ aliases: String) {
            self.key = key
            self.english = english
            self.italian = italian
            self.visual = visual.components(separatedBy: "|")
            self.aliases = aliases.components(separatedBy: "|")
        }
    }

    private static let topics = [
        Topic("desert", "Desert", "Deserto", "desert|dune|dunes|sand dune", "desert|deserts|dune|dunes|deserto|deserti|duna"),
        Topic("sand", "Sand", "Sabbia", "sand|sandy|dune|dunes|desert", "sand|sandy|sabbia|sabbioso|sabbiose|sabbioso"),
        Topic("wildlife", "Wildlife", "Fauna selvatica", "wildlife|wild animal|elephant|giraffe|zebra|oryx|antelope|springbok|lion|leopard|cheetah|rhinoceros|rhino|hippopotamus|ostrich|flamingo|hyena|wildebeest|gazelle|buffalo|jackal|baboon", "wildlife|safari|fauna|selvatici|selvatica|animali|animals"),
        Topic("water", "Water", "Acqua", "water|lake|river|ocean|sea|lagoon|waterfall|pond|waterhole|coast|shore|beach", "water|lake|river|ocean|sea|lagoon|coast|beach|shore|acqua|lago|fiume|oceano|mare|laguna|costa|spiaggia|pozza"),
        Topic("town", "Town", "Città", "town|city|urban|street|cityscape|village|downtown|skyline", "town|city|village|street|urban|città|paese|villaggio|vie|urbano|centro storico"),
        Topic("road", "On the road", "In viaggio", "road|highway|car|truck|vehicle|jeep|automobile|freeway", "road|drive|driving|highway|car|jeep|vehicle|strada|strade|auto|macchina|fuoristrada|guidando|in viaggio"),
        Topic("people", "People", "Persone", "person|people|group of people|human|crowd|portrait|selfie|family", "person|people|together|family|friends|portrait|selfie|persone|persona|insieme|famiglia|amici|ritratto"),
        Topic("outdoors", "Outdoors", "All’aperto", "outdoor|outdoors|landscape|savanna|savannah|mountain|valley|forest|canyon|grassland|desert|dune", "outdoors|outdoor|landscape|nature|savanna|savannah|all aperto|aperto|natura|paesaggio|paesaggi|savana"),
        Topic("mountains", "Mountains", "Montagne", "mountain|mountains|mountain range|canyon|cliff|valley", "mountain|mountains|canyon|valley|cliff|montagna|montagne|valle|gola|parete"),
        Topic("sunset", "Sunrise or sunset", "Alba o tramonto", "sunset|sunrise|dusk|dawn", "sunset|sunrise|dawn|dusk|alba|tramonto|crepuscolo"),
        Topic("birds", "Birds", "Uccelli", "bird|birds|flamingo|ostrich|eagle|vulture|pelican", "bird|birds|uccello|uccelli|avifauna")
    ]

    static func analyze(url: URL) async throws -> PhotoAnalysis {
        try Task.checkCancellation()
        return try autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }

            let request = VNClassifyImageRequest()
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            try Task.checkCancellation()
            let observations = (request.results ?? []).filter { $0.confidence >= 0.25 }
                .sorted { lhs, rhs in
                    if lhs.confidence == rhs.confidence { return lhs.identifier < rhs.identifier }
                    return lhs.confidence > rhs.confidence
                }
            var observed = Set<String>()
            let labels = observations.prefix(18).compactMap { observation -> String? in
                let label = observation.identifier.replacingOccurrences(of: "_", with: " ")
                return observed.insert(label).inserted ? label : nil
            }
            let normalized = labels.map(normalize)
            let concepts = topics.filter { topic in
                topic.visual.contains { word in normalized.contains { contains($0, phrase: word) } }
            }.map(\.key)
            return PhotoAnalysis(labels: labels, concepts: concepts)
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func contains(_ text: String, phrase: String) -> Bool {
        !phrase.isEmpty && (" " + text + " ").contains(" " + phrase + " ")
    }

    private static let translations = [
        "elephant": ["elefante", "elefanti", "elephants"], "giraffe": ["giraffa", "giraffe", "giraffes"],
        "zebra": ["zebre", "zebras"], "lion": ["leone", "leoni", "lions"], "oryx": ["orice", "orici"],
        "ostrich": ["struzzo", "struzzi", "ostriches"], "rhinoceros": ["rinoceronte", "rinoceronti", "rhino"],
        "flamingo": ["fenicottero", "fenicotteri", "flamingos"], "leopard": ["leopardo", "leopardi", "leopards"],
        "cheetah": ["ghepardo", "ghepardi", "cheetahs"], "antelope": ["antilope", "antilopi", "antelopes"]
    ]

    static func score(_ analysis: PhotoAnalysis, for text: String) -> Double {
        let query = normalize(text)
        guard !query.isEmpty else { return 0 }
        let labels = analysis.labels.map(normalize)
        var score = 0.0
        for (rank, label) in labels.enumerated() where label.count > 2 {
            if contains(query, phrase: label) { score += 2.0 / (1 + Double(rank) * 0.1) }
        }
        for term in translations.keys.sorted() where labels.contains(where: { contains($0, phrase: term) }) {
            if translations[term]!.contains(where: { contains(query, phrase: $0) && $0 != term }) { score += 2 }
        }
        for topic in topics where analysis.concepts.contains(topic.key) {
            if topic.aliases.contains(where: { contains(query, phrase: normalize($0)) }) { score += 1 }
        }
        return score
    }

    static func displayName(for concept: String, language: String) -> String {
        guard let topic = topics.first(where: { $0.key == concept }) else { return concept }
        return language.lowercased().hasPrefix("it") ? topic.italian : topic.english
    }
}
