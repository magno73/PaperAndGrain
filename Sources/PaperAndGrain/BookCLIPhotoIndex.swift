import Foundation

enum BookCLIPhotoIndex {
    static let usage = [
        "photos PROJECT.papergrain [--photo UUID] [--filter QUERY] [--limit N] [--details] [--unused]",
        "analyze PROJECT.papergrain [--photo UUID]... [--force] [--output OUTPUT.papergrain]",
        "rank PROJECT.papergrain QUERY [--limit N] [--unused]",
        "similar PROJECT.papergrain UUID [--by subjects|near-duplicate] [--limit N] [--unused]",
    ]

    private struct Record: Encodable {
        let id: UUID
        let name: String
        let assetPath: String
        let capturedAt: String?
        let width: Int
        let height: Int
        let caption: String?
        let pages: [UUID]
        let onFrontCover: Bool
        let onBackCover: Bool
        let labels: [String]
        let concepts: [String]
        let analysisRevision: Int?
        let analysis: PhotoAnalysis?
    }

    private struct Index {
        let book: Book
        let directory: URL
        let pages: [UUID: [UUID]]
        let dates = ISO8601DateFormatter()

        init(_ directory: URL) throws {
            self.directory = directory
            book = try BookStorage.read(from: directory)
            var references: [UUID: [UUID]] = [:]
            for page in book.pages {
                for id in Set(page.photoIDs) { references[id, default: []].append(page.id) }
            }
            pages = references
        }

        func record(_ photo: BookPhoto, details: Bool = false) -> Record {
            Record(id: photo.id, name: photo.name, assetPath: asset(for: photo).path,
                   capturedAt: photo.capturedAt.map(dates.string(from:)), width: photo.pixelWidth, height: photo.pixelHeight,
                   caption: photo.caption, pages: pages[photo.id] ?? [], onFrontCover: photo.id == book.cover?.frontPhotoID,
                   onBackCover: photo.id == book.cover?.backPhotoID, labels: photo.analysis?.labels ?? [],
                   concepts: photo.analysis?.concepts ?? [], analysisRevision: photo.analysis?.revision,
                   analysis: details ? photo.analysis : nil)
        }

        func isUnused(_ photo: BookPhoto) -> Bool {
            pages[photo.id] == nil && photo.id != book.cover?.frontPhotoID && photo.id != book.cover?.backPhotoID
        }

        func asset(for photo: BookPhoto) -> URL {
            BookStorage.assetURL(filename: photo.filename, in: directory)
        }
    }

    private struct Ranked: Encodable {
        let photo: Record
        let score: Double
        let evidence: [PhotoMatchEvidence]
    }

    private struct Neighbor: Encodable {
        let photo: Record
        let score: Double
        let subjectSimilarity: Double?
        let perceptualDistance: Double?
    }

    private struct AnalysisResult: Encodable {
        let id: UUID
        let name: String
        let status: String
        let analysis: PhotoAnalysis?
        let error: String?
    }

    private struct AnalysisReport: Encodable {
        let revision: Int
        let analyzed: Int
        let reused: Int
        let failed: Int
        let project: String?
        let photos: [AnalysisResult]
    }

    private struct Options {
        var photoIDs: Set<UUID> = []
        var output: URL?
        var limit: Int?
        var query: String?
        var by = "subjects"
        var details = false
        var force = false
        var unused = false

        enum Option: String {
            case photo = "--photo", filter = "--filter", limit = "--limit", details = "--details", unused = "--unused"
            case force = "--force", output = "--output", by = "--by"
        }

        init(_ args: ArraySlice<String>, allowed: Set<Option>, relativeTo directory: URL) throws {
            var arguments = args.makeIterator()
            var used: Set<Option> = []
            while let argument = arguments.next() {
                guard let option = Option(rawValue: argument), allowed.contains(option),
                      used.insert(option).inserted || option == .photo else {
                    throw BookCLI.Failure("Unexpected or repeated option: \(argument)")
                }
                func value() throws -> String {
                    guard let value = arguments.next(), !value.hasPrefix("--") else {
                        throw BookCLI.Failure("Missing value for \(argument)")
                    }
                    return value
                }
                switch option {
                case .details: details = true
                case .force: force = true
                case .unused: unused = true
                case .limit:
                    guard let number = Int(try value()), (1...500).contains(number) else {
                        throw BookCLI.Failure("--limit must be between 1 and 500")
                    }
                    limit = number
                case .photo:
                    let text = try value()
                    guard let id = UUID(uuidString: text), photoIDs.insert(id).inserted else {
                        throw BookCLI.Failure("Invalid or duplicate photo UUID: \(text)")
                    }
                case .filter: query = try value()
                case .output: output = BookCLI.url(try value(), relativeTo: directory)
                case .by:
                    let text = try value()
                    guard ["subjects", "near-duplicate"].contains(text) else {
                        throw BookCLI.Failure("Expected --by subjects or near-duplicate")
                    }
                    by = text
                }
            }
        }
    }

    private enum Command: String { case photos, analyze, rank, similar }

    static func run(command name: String, arguments: [String], currentDirectory: URL) async throws -> Data? {
        guard let command = Command(rawValue: name) else { return nil }
        guard let source = arguments.first, !source.hasPrefix("--") else { throw BookCLI.Failure("Expected a project path") }
        let index = try Index(BookCLI.url(source, relativeTo: currentDirectory))
        switch command {
        case .photos:
            let options = try Options(arguments.dropFirst(), allowed: [.photo, .filter, .limit, .details, .unused],
                                      relativeTo: currentDirectory)
            let selection = try selected(options, in: index).filter { photo in
                guard let query = options.query, !query.isEmpty else { return true }
                return photo.name.localizedStandardContains(query)
                    || photo.analysis.map { PhotoAnalyzer.score($0, for: query) > 0 } == true
            }
            return try BookCLI.encode(selection.prefix(options.limit ?? selection.count).map {
                index.record($0, details: options.details || !options.photoIDs.isEmpty)
            })
        case .analyze:
            let options = try Options(arguments.dropFirst(), allowed: [.photo, .force, .output], relativeTo: currentDirectory)
            return try BookCLI.encode(await analyze(index, options: options))
        case .rank:
            guard arguments.count >= 2, !arguments[1].hasPrefix("--"),
                  !arguments[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookCLI.Failure("Expected a non-empty query after the project path")
            }
            let options = try Options(arguments.dropFirst(2), allowed: [.limit, .unused], relativeTo: currentDirectory)
            return try BookCLI.encode(rank(index, query: arguments[1], options: options))
        case .similar:
            guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else {
                throw BookCLI.Failure("Expected a photo UUID after the project path")
            }
            let options = try Options(arguments.dropFirst(2), allowed: [.limit, .by, .unused], relativeTo: currentDirectory)
            return try BookCLI.encode(similar(index, id: id, options: options))
        }
    }

    private static func selected(_ options: Options, in index: Index) throws -> [BookPhoto] {
        guard options.photoIDs.isSubset(of: Set(index.book.photos.map(\.id))) else {
            throw BookCLI.Failure("At least one photo UUID does not belong to this project")
        }
        return index.book.photos.filter {
            (options.photoIDs.isEmpty || options.photoIDs.contains($0.id)) && (!options.unused || index.isUnused($0))
        }
    }

    private static func analyze(_ index: Index, options: Options) async throws -> AnalysisReport {
        // Check the destination before the slow part, so a typo does not cost a full analysis.
        if let output = options.output { try BookCLIEditing.checkOutput(output, source: index.directory) }
        let photos = try selected(options, in: index)
        var results: [AnalysisResult] = []
        var revisions: [UUID: (filename: String, analysis: PhotoAnalysis)] = [:]
        let assetRoot = index.directory.resolvingSymlinksInPath().appendingPathComponent("assets", isDirectory: true)
        for photo in photos {
            try Task.checkCancellation()
            if !options.force, let analysis = photo.analysis, analysis.revision >= PhotoAnalysis.currentRevision {
                results.append(AnalysisResult(id: photo.id, name: photo.name, status: "reused", analysis: analysis, error: nil))
                continue
            }
            do {
                let url = index.asset(for: photo)
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path == assetRoot.appendingPathComponent(photo.filename).path,
                      try resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw BookCLI.Failure("Image asset is unavailable inside the project")
                }
                let analysis = try await PhotoAnalyzer.analyze(url: resolved)
                revisions[photo.id] = (photo.filename, analysis)
                results.append(AnalysisResult(id: photo.id, name: photo.name, status: "analyzed", analysis: analysis, error: nil))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(AnalysisResult(id: photo.id, name: photo.name, status: "failed", analysis: nil,
                                              error: error.localizedDescription))
            }
        }
        if let output = options.output {
            _ = try BookCLIEditing.derive(source: index.directory, output: output) { book, _ in
                let actual = Dictionary(uniqueKeysWithValues: book.photos.map { ($0.id, $0.filename) })
                guard revisions.allSatisfy({ actual[$0.key] == $0.value.filename }) else {
                    throw BookCLI.Failure("Project photo references changed during analysis")
                }
                for i in book.photos.indices {
                    if let revised = revisions[book.photos[i].id] { book.photos[i].analysis = revised.analysis }
                }
            }
        }
        let reused = results.filter { $0.status == "reused" }.count
        return AnalysisReport(revision: PhotoAnalysis.currentRevision, analyzed: revisions.count, reused: reused,
                              failed: results.count - revisions.count - reused, project: options.output?.path, photos: results)
    }

    private static func rank(_ index: Index, query: String, options: Options) throws -> [Ranked] {
        let ranked = try selected(options, in: index).compactMap { photo -> Ranked? in
            guard let analysis = photo.analysis else { return nil }
            let evidence = PhotoAnalyzer.matches(analysis, for: query)
            guard !evidence.isEmpty else { return nil }
            return Ranked(photo: index.record(photo), score: evidence.reduce(0) { $0 + $1.score }, evidence: evidence)
        }.sorted {
            if $0.score == $1.score { return $0.photo.id.uuidString < $1.photo.id.uuidString }
            return $0.score > $1.score
        }
        return Array(ranked.prefix(options.limit ?? 20))
    }

    private static func similar(_ index: Index, id: UUID, options: Options) throws -> [Neighbor] {
        guard let reference = index.book.photo(id), let analysis = reference.analysis else {
            throw BookCLI.Failure("Expected an analyzed photo from this project")
        }
        if options.by == "near-duplicate", PhotoAnalyzer.distance(analysis, analysis) == nil {
            throw BookCLI.Failure("Run analyze to update the reference photo before searching near-duplicates")
        }
        let neighbors = try selected(options, in: index).compactMap { photo -> Neighbor? in
            guard photo.id != id, let candidate = photo.analysis else { return nil }
            let subjects = PhotoAnalyzer.relatedness(analysis, candidate)
            let distance = PhotoAnalyzer.distance(analysis, candidate)
            let score = options.by == "subjects" ? subjects : distance.map { 1 - $0 }
            guard let score, score > 0 else { return nil }
            return Neighbor(photo: index.record(photo), score: score, subjectSimilarity: subjects, perceptualDistance: distance)
        }.sorted {
            if $0.score == $1.score { return $0.photo.id.uuidString < $1.photo.id.uuidString }
            return $0.score > $1.score
        }
        return Array(neighbors.prefix(options.limit ?? 20))
    }
}
