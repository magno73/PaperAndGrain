import Foundation
import ImageIO
import Vision

struct PhotoAnalysis: Codable, Hashable, Sendable {
    static let currentRevision = 2
    var labels: [String]
    var concepts: [String]
    var revision: Int = 1
    var classifications: [PhotoClassification]?
    var detections: [PhotoDetection]?
    var recognizedText: [PhotoText]?
    var visual: PhotoVisualSignals?
    var unavailableSignals: [String]?
}

struct PhotoMatchEvidence: Codable, Hashable, Sendable {
    var source, value: String
    var score: Double
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
                    kCGImageSourceThumbnailMaxPixelSize: 1600,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }

            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            var unavailable: [String] = []
            func perform(_ request: VNRequest, _ name: String) throws -> Bool {
                try Task.checkCancellation()
                do {
                    try handler.perform([request])
                    return true
                } catch {
                    unavailable.append(name)
                    return false
                }
            }
            let classifier = VNClassifyImageRequest()
            var classes: [PhotoClassification] = []
            if try perform(classifier, "classification") {
                let candidates = (classifier.results ?? []).filter { $0.confidence >= 0.06 }
                    .sorted { $0.confidence == $1.confidence ? $0.identifier < $1.identifier : $0.confidence > $1.confidence }
                var seen = Set<String>()
                for item in candidates {
                    let label = item.identifier.replacingOccurrences(of: "_", with: " ")
                    if seen.insert(label).inserted {
                        classes.append(PhotoClassification(label: label, confidence: Double(item.confidence)))
                    }
                    if classes.count == 48 { break }
                }
            }
            var detections: [PhotoDetection] = []
            let humans = VNDetectHumanRectanglesRequest()
            humans.upperBodyOnly = false
            if try perform(humans, "people") {
                detections += (humans.results ?? []).map {
                    PhotoDetection(kind: "person", label: "person", confidence: Double($0.confidence), box: PhotoBox($0.boundingBox))
                }
            }
            let faces = VNDetectFaceRectanglesRequest()
            if try perform(faces, "faces") {
                detections += (faces.results ?? []).map {
                    PhotoDetection(kind: "face", label: "face", confidence: Double($0.confidence), box: PhotoBox($0.boundingBox))
                }
            }
            let animals = VNRecognizeAnimalsRequest()
            if try perform(animals, "animals") {
                detections += (animals.results ?? []).compactMap {
                    guard let best = $0.labels.first else { return nil }
                    return PhotoDetection(kind: "animal", label: best.identifier.lowercased(),
                                          confidence: Double(best.confidence), box: PhotoBox($0.boundingBox))
                }
            }
            let ocr = VNRecognizeTextRequest()
            ocr.recognitionLevel = .accurate
            ocr.automaticallyDetectsLanguage = true
            var words: [PhotoText] = []
            if try perform(ocr, "text") {
                words = (ocr.results ?? []).compactMap {
                    guard let candidate = $0.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
                    return PhotoText(text: candidate.string, confidence: Double(candidate.confidence), box: PhotoBox($0.boundingBox))
                }
            }
            let labels = classes.map(\.label)
            var evidence = classes.filter { $0.confidence >= 0.18 }.map { normalize($0.label) }
            evidence += detections.map { $0.kind == "face" ? "person" : normalize($0.label) }
            let concepts = topics.filter { topic in
                topic.visual.contains { word in evidence.contains { contains($0, phrase: word) } }
            }.map(\.key)
            let visual = PhotoVisualSignals.measure(image)
            if visual == nil { unavailable.append("visual") }
            try Task.checkCancellation()
            return PhotoAnalysis(labels: labels, concepts: concepts, revision: PhotoAnalysis.currentRevision,
                                 classifications: classes, detections: detections, recognizedText: words,
                                 visual: visual, unavailableSignals: unavailable)
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
        "dog": ["cane", "cani", "dogs"], "cat": ["gatto", "gatti", "cats"],
        "face": ["viso", "volto", "volti", "facce", "faces"], "tree": ["albero", "alberi", "trees"],
        "boat": ["barca", "barche", "boats"], "bridge": ["ponte", "ponti", "bridges"],
        "building": ["edificio", "edifici", "buildings"], "sign": ["cartello", "cartelli", "signs"],
        "cheetah": ["ghepardo", "ghepardi", "cheetahs"], "antelope": ["antilope", "antilopi", "antelopes"],
        "sand dune": ["duna", "dune", "sand dunes"], "desert": ["deserto", "deserti"]
    ]

    private static func subjectWeights(_ analysis: PhotoAnalysis) -> [String: Double] {
        var evidence: [String: Double] = [:]
        for item in analysis.classifications ?? [] {
            evidence[normalize(item.label)] = item.confidence
        }
        for (rank, label) in analysis.labels.enumerated() where evidence[normalize(label)] == nil {
            evidence[normalize(label)] = 1 / (1 + Double(rank) * 0.1)
        }
        for item in analysis.detections ?? [] {
            for term in [item.kind, item.label] {
                let key = normalize(term)
                evidence[key] = max(evidence[key] ?? 0, item.confidence)
            }
        }
        return evidence
    }

    static func relatedness(_ lhs: PhotoAnalysis, _ rhs: PhotoAnalysis) -> Double? {
        let a = subjectWeights(lhs), b = subjectWeights(rhs)
        let normA = a.values.reduce(0) { $0 + $1 * $1 }
        let normB = b.values.reduce(0) { $0 + $1 * $1 }
        guard normA > 0, normB > 0 else { return nil }
        let dot = a.reduce(0.0) { $0 + $1.value * (b[$1.key] ?? 0) }
        return min(1, dot / sqrt(normA * normB))
    }

    static func score(_ analysis: PhotoAnalysis, for text: String) -> Double {
        matches(analysis, for: text).reduce(0) { $0 + $1.score }
    }

    static func matches(_ analysis: PhotoAnalysis, for text: String) -> [PhotoMatchEvidence] {
        let query = normalize(text)
        guard !query.isEmpty else { return [] }
        let evidence = subjectWeights(analysis)
        var matches: [PhotoMatchEvidence] = []
        for label in evidence.keys.sorted() where label.count > 2 {
            let weight = 0.55 + 1.45 * (evidence[label] ?? 0)
            if contains(query, phrase: label) {
                matches.append(PhotoMatchEvidence(source: "subject", value: label, score: weight))
            } else if translations.contains(where: { term, aliases in
                contains(label, phrase: term) && aliases.contains { contains(query, phrase: $0) }
            }) {
                matches.append(PhotoMatchEvidence(source: "subject", value: label, score: weight))
            }
        }
        let queryWords = Set(query.components(separatedBy: " ").filter { $0.count >= 3 })
        let stopWords: Set<String> = ["the", "and", "with", "for", "was", "that", "con", "per", "del", "della", "una", "nel", "alla", "gli", "che"]
        var textWeights: [String: Double] = [:]
        for line in analysis.recognizedText ?? [] {
            let shared = queryWords.intersection(normalize(line.text).components(separatedBy: " ")).subtracting(stopWords)
            for word in shared { textWeights[word] = max(textWeights[word] ?? 0, line.confidence) }
        }
        for (word, weight) in textWeights.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }).prefix(4) {
            matches.append(PhotoMatchEvidence(source: "text", value: word, score: 0.65 + weight))
        }
        for topic in topics where analysis.concepts.contains(topic.key) {
            if topic.aliases.contains(where: { contains(query, phrase: normalize($0)) }) {
                matches.append(PhotoMatchEvidence(source: "concept", value: topic.key, score: 0.45))
            }
        }
        return matches.sorted { $0.score > $1.score }
    }

    static func distance(_ lhs: PhotoAnalysis, _ rhs: PhotoAnalysis) -> Double? {
        guard let l = lhs.visual?.perceptualHash, l.count == 16, let a = UInt64(l, radix: 16),
              let r = rhs.visual?.perceptualHash, r.count == 16, let b = UInt64(r, radix: 16) else { return nil }
        return Double((a ^ b).nonzeroBitCount) / 64
    }

    static func displayName(for concept: String, language: String) -> String {
        guard let topic = topics.first(where: { $0.key == concept }) else { return concept }
        return language.lowercased().hasPrefix("it") ? topic.italian : topic.english
    }
}
