import Foundation

/// The result of the preflight check and the model of one problem in it. Nothing here depends on
/// SwiftUI: the editor's Issues list, the export sheet and the command line read the same values.
extension BookPDF {
    /// Problems found before an export. Blockers make the export fail and must be fixed first;
    /// warnings describe a weaker print. Each issue is localized when it is shown.
    struct Preflight: Equatable, Sendable {
        var blockers: [PreflightIssue] = []
        var warnings: [PreflightIssue] = []

        var isClean: Bool { blockers.isEmpty && warnings.isEmpty }

        /// Issues grouped by where they are, in book order, for the list the author reads.
        func groups(of severity: IssueSeverity) -> [IssueGroup] {
            IssueGroup.groups(severity == .blocker ? blockers : warnings)
        }
    }

    enum IssueSeverity: Sendable {
        case blocker, warning
    }

    /// The object of a page (or of the cover) an issue is about, so the editor can select it.
    enum IssueTarget: Hashable, Sendable {
        case photo(UUID)
        case textBox(UUID)
        /// The page's heading and story.
        case story
        /// The caption of a photo, by the photo's id.
        case caption(UUID)
        case cover(front: Bool)

        /// Stable text for building an issue's id.
        var key: String {
            switch self {
            case let .photo(id): "photo:" + id.uuidString
            case let .textBox(id): "box:" + id.uuidString
            case .story: "story"
            case let .caption(id): "caption:" + id.uuidString
            case let .cover(front): front ? "cover:front" : "cover:back"
            }
        }
    }

    /// Where the editor goes to show an issue.
    enum IssueDestination: Equatable, Sendable {
        case page(UUID)
        case cover(front: Bool)
    }

    /// Issues that share a place, shown under one heading.
    struct IssueGroup: Identifiable, Equatable, Sendable {
        let location: PreflightIssue.Location?
        let issues: [PreflightIssue]

        var id: String {
            switch location {
            case nil: "book"
            case let .page(number)?: "page:" + String(number)
            case .cover?: "cover"
            }
        }

        /// Book-wide issues first, then pages in page order, then the cover. Order inside a group is kept.
        static func groups(_ issues: [PreflightIssue]) -> [IssueGroup] {
            func rank(_ location: PreflightIssue.Location?) -> Int {
                switch location {
                case nil: -1
                case let .page(number)?: number
                case .cover?: Int.max
                }
            }
            return Dictionary(grouping: issues, by: \.location)
                .map { IssueGroup(location: $0.key, issues: $0.value) }
                .sorted { rank($0.location) < rank($1.location) }
        }
    }

    /// One problem of the preflight: where it is, and what it is.
    struct PreflightIssue: Equatable, Sendable, Identifiable {
        enum Location: Hashable, Sendable {
            /// The page number shown in the editor.
            case page(Int)
            case cover
        }

        /// Add a case here and every `switch` over a problem stops compiling until it is handled:
        /// `kind`, `symbol` and `message`, and the editor's fix action.
        enum Problem: Equatable, Sendable {
            case invalidDimensions
            case missingPhoto
            /// The photo's file is not in the book package; the name is the photo's.
            case missingFile(String)
            /// The LUT cannot be read; the name is the LUT file's, or the photo's when the LUT has none.
            case unreadableLUT(String)
            case lowResolution(photo: String, ppi: Double, target: Double)
            case textOverflows
            /// A heading, story or text box whose frame crosses the safe line.
            case textOutsideSafeMargin
            /// A photo edge that stops inside the trim by less than the bleed, so a cutting error would
            /// show paper; the distance is in millimetres.
            case photoNearEdge(photo: String, distanceMM: Double)
            /// Blank pages added so the imposition lines up, by sheet position.
            case blankPages([Int])

            /// The kind without its details, for the issue's id.
            var kind: String {
                switch self {
                case .invalidDimensions: "invalidDimensions"
                case .missingPhoto: "missingPhoto"
                case .missingFile: "missingFile"
                case .unreadableLUT: "unreadableLUT"
                case .lowResolution: "lowResolution"
                case .textOverflows: "textOverflows"
                case .textOutsideSafeMargin: "textOutsideSafeMargin"
                case .photoNearEdge: "photoNearEdge"
                case .blankPages: "blankPages"
                }
            }

            /// An SF Symbol name for the kind of problem.
            var symbol: String {
                switch self {
                case .invalidDimensions: "ruler"
                case .missingPhoto: "photo.badge.exclamationmark"
                case .missingFile: "questionmark.folder"
                case .unreadableLUT: "camera.filters"
                case .lowResolution: "arrow.down.right.and.arrow.up.left"
                case .textOverflows: "text.append"
                case .textOutsideSafeMargin: "text.badge.minus"
                case .photoNearEdge: "photo.badge.exclamationmark"
                case .blankPages: "doc.on.doc"
                }
            }
        }

        var location: Location?
        var problem: Problem
        /// The page the issue belongs to; the page number in `location` can change, the id cannot.
        var pageID: UUID?
        var target: IssueTarget?
        /// Which occurrence of the target on the page, when a photo is placed twice (0 for the first).
        var occurrence = 0
        /// The first words of the text box the issue is about, to tell boxes apart in a message.
        var excerpt: String?

        init(location: Location? = nil, problem: Problem, pageID: UUID? = nil, target: IssueTarget? = nil,
             occurrence: Int = 0, excerpt: String? = nil) {
            self.location = location
            self.problem = problem
            self.pageID = pageID
            self.target = target
            self.occurrence = occurrence
            self.excerpt = excerpt
        }

        /// Built from the kind, the page and the object, so a list keeps its rows between runs.
        var id: String {
            [problem.kind, pageID?.uuidString ?? "-", target?.key ?? "-"]
                .joined(separator: "|") + (occurrence > 0 ? "|" + String(occurrence) : "")
        }

        /// The page or cover face to show, or nil for an issue about the whole book.
        func destination(in book: Book) -> IssueDestination? {
            if case let .cover(front)? = target { return .cover(front: front) }
            if location == .cover { return .cover(front: true) }
            if let pageID, book.pages.contains(where: { $0.id == pageID }) { return .page(pageID) }
            let owner: BookPage? = switch target {
            case let .photo(id)?, let .caption(id)?: book.pages.first { $0.photoIDs.contains(id) }
            case let .textBox(id)?: book.pages.first { $0.textBoxes?.contains { $0.id == id } == true }
            case .story?, .cover?, nil: nil
            }
            return owner.map { .page($0.id) }
        }

        /// What overflows, so two lines of one page are never identical: the story, the box's first
        /// words, or the face of the cover.
        private func overflowSubject(language: String) -> String? {
            switch target {
            case .story?: L10n.string("Story", language: language)
            case .textBox?:
                excerpt.map { "“" + $0 + "”" } ?? L10n.string("Text Box", language: language)
            case let .cover(front)?: L10n.string(front ? "Front" : "Back", language: language)
            case .photo?, .caption?, nil: nil
            }
        }

        /// "location · subject · problem", in `language`. The CLI reads it in English. A list that
        /// already shows the place under a heading leaves it out.
        func message(language: String, includingPlace: Bool = true) -> String {
            let place: String? = switch location {
            case let .page(number)? where includingPlace: "p. " + String(number)
            case .cover? where includingPlace: L10n.string("Cover", language: language)
            default: nil
            }
            let parts: [String?] = switch problem {
            case .invalidDimensions: [place, L10n.string("Invalid print dimensions", language: language)]
            case .missingPhoto: [place, L10n.string("Missing photo", language: language)]
            case let .missingFile(name): [place, name, L10n.string("Photo file missing", language: language)]
            case let .unreadableLUT(name): [place, name, L10n.string("Unreadable LUT", language: language)]
            case let .lowResolution(photo, ppi, target):
                [place, photo, String(format: "%.0f ppi < %.0f ppi", ppi, target)]
            case .textOverflows: [place, overflowSubject(language: language), L10n.string("Text overflows", language: language)]
            case .textOutsideSafeMargin:
                [place, overflowSubject(language: language), L10n.string("Text crosses the safe margin", language: language)]
            case let .photoNearEdge(photo, distanceMM):
                [place, photo, L10n.format("Photo ends %.1f mm inside the trim. Move it to the edge or further in.",
                                           language: language, [distanceMM])]
            case let .blankPages(pages):
                [place, L10n.string("Blank pages for alignment", language: language),
                 pages.map(String.init).joined(separator: ", ")]
            }
            return parts.compactMap { $0 }.joined(separator: " · ")
        }
    }
}
