import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BookPDF {
    private static let pointsPerMM = 72.0 / 25.4

    enum ExportError: LocalizedError {
        case invalidBook
        case missingImage(String)
        case textOverflow(Int)
        case coverTextOverflow
        case sizeNotOffered
        case missingMeasure(PrintMeasure)

        /// In the interface language (English in the CLI).
        var errorDescription: String? {
            let language = L10n.interfaceLanguage
            return switch self {
            case .invalidBook: L10n.string("Could not create the PDF", language: language)
            case let .missingImage(name): L10n.format("Photo unavailable — %@", language: language, [name])
            case let .textOverflow(number): L10n.format("Text overflows on page %lld", language: language, [number])
            case .coverTextOverflow: L10n.string("Text overflows on the cover", language: language)
            case .sizeNotOffered: L10n.string("The print service does not offer the book’s size", language: language)
            case let .missingMeasure(measure):
                PreflightIssue(problem: .missingMeasure(measure)).message(language: language)
            }
        }
    }

    /// `progress` receives the completed fraction, from 0 to 1, after each sheet. It is called on the
    /// exporting thread.
    static func write(_ book: Book, directory: URL, to destination: URL,
                      progress: (@Sendable (Double) -> Void)? = nil) throws {
        let meter = ProgressMeter(total: sheetCount(book, settings: nil, firstPageRight: false), report: progress)
        try render(book, directory: directory, output: Output(settings: nil), to: destination, meter: meter)
        meter.finish()
    }

    static func writePrint(_ book: Book, directory: URL, to destination: URL,
                           progress: (@Sendable (Double) -> Void)? = nil) throws {
        let settings = book.printSettings ?? PrintSettings()
        let meter = ProgressMeter(total: sheetCount(book, settings: settings, firstPageRight: false) + (book.cover == nil ? 0 : 1),
                                  report: progress)
        let bleed = PageBleed(uniform: settings.bleedMM * pointsPerMM)
        try writeFolder(destination, names: ["Interior.pdf", "Cover.pdf"]) { scratch in
            try render(book, directory: directory, output: Output(settings: settings, bleed: bleed),
                       to: scratch.appendingPathComponent("Interior.pdf"), meter: meter)
            if let cover = book.cover {
                try render(book, directory: directory,
                           output: Output(settings: settings, bleed: bleed, genericCover: cover, interior: false),
                           to: scratch.appendingPathComponent("Cover.pdf"), meter: meter)
            }
        }
        meter.finish()
    }

    /// Writes the files of a print-service product (`PrintPlan`): one PDF at `destination`, or a folder
    /// with the interior and cover files the printer names. Every product goes through this one path.
    static func write(_ book: Book, directory: URL, plan: PrintPlan, to destination: URL,
                      progress: (@Sendable (Double) -> Void)? = nil) throws {
        guard plan.size(for: book) != nil else { throw ExportError.sizeNotOffered }
        let settings = plan.interiorSettings(for: book)
        let interiorPages = leaves(book.pages, settings: settings, firstPageRight: plan.firstPageRight).count
        let kind = plan.coverKind(for: book)
        let flat = kind == .flat ? try flatCover(book, plan: plan, interiorPages: interiorPages) : nil
        let bleed = PageBleed(plan.profile.interior.bleed)
        let coverPages = kind == .interiorPages
        let meter = ProgressMeter(total: sheetCount(book, settings: settings, firstPageRight: plan.firstPageRight)
                                  + (flat == nil ? 0 : 1) + (coverPages ? 2 : 0), report: progress)
        let interior = Output(settings: settings, bleed: bleed, coverPages: coverPages, firstPageRight: plan.firstPageRight)
        let files = plan.profile.files
        switch files.arrangement {
        case .single:
            var single = interior
            single.flatCover = flat
            try render(book, directory: directory, output: single, to: destination, meter: meter)
        case .separate:
            let names = [files.interiorName] + (flat == nil ? [] : [files.coverName])
            try writeFolder(destination, names: names) { scratch in
                try render(book, directory: directory, output: interior,
                           to: scratch.appendingPathComponent(files.interiorName), meter: meter)
                if let flat {
                    try render(book, directory: directory,
                               output: Output(settings: settings, bleed: bleed, flatCover: flat, interior: false),
                               to: scratch.appendingPathComponent(files.coverName), meter: meter)
                }
            }
        }
        meter.finish()
    }

    /// Renders files into a scratch folder and moves it to `destination` when complete. Only a folder
    /// that holds nothing but a previous export of the same names (and `.DS_Store`) is replaced.
    private static func writeFolder(_ destination: URL, names: [String], render: (URL) throws -> Void) throws {
        let fm = FileManager.default
        // Check the destination before rendering: only a previous package may be replaced.
        if fm.fileExists(atPath: destination.path) {
            let previous = Set(names + [".DS_Store"])
            guard let contents = try? fm.contentsOfDirectory(atPath: destination.path),
                  Set(contents).isSubset(of: previous) else { throw CocoaError(.fileWriteFileExists) }
        }
        let scratch = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        try render(scratch)
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: scratch)
        } else {
            try fm.moveItem(at: scratch, to: destination)
        }
    }

    /// The flat cover of a product, in points: faces, hinges and spine from the profile and the author's
    /// measures. A measure that is neither typed nor computable stops the export.
    private static func flatCover(_ book: Book, plan: PrintPlan, interiorPages: Int) throws -> FlatCover {
        let rules = plan.coverRules(for: book)
        func measure(_ kind: PrintMeasure) throws -> Double {
            guard let mm = plan.value(kind, for: book, interiorPages: interiorPages) else { throw ExportError.missingMeasure(kind) }
            return mm * pointsPerMM
        }
        let panel = rules.panel.map { CGSize(width: $0.widthMM.mm * pointsPerMM, height: $0.heightMM.mm * pointsPerMM) }
            ?? book.format.pageSize
        let bleed = rules.bleed ?? PrintProfile.Edges(0)
        return FlatCover(panel: panel, hinge: try measure(.hinge), spine: try measure(.spine), wrap: try measure(.wrap),
                         bleedTop: bleed.top.mm * pointsPerMM, bleedBottom: bleed.bottom.mm * pointsPerMM,
                         bleedOuter: bleed.outer.mm * pointsPerMM)
    }

    /// Counts rendered sheets and reports the completed fraction.
    private final class ProgressMeter {
        private let total: Int
        private var done = 0
        private let report: (@Sendable (Double) -> Void)?

        init(total: Int, report: (@Sendable (Double) -> Void)?) {
            self.total = max(1, total)
            self.report = report
            report?(0)
        }

        func sheetDone() {
            done += 1
            report?(min(1, Double(done) / Double(total)))
        }

        func finish() { report?(1) }
    }

    private static func sheetCount(_ book: Book, settings: PrintSettings?, firstPageRight: Bool) -> Int {
        let slots = leaves(book.pages, settings: settings, firstPageRight: firstPageRight).count
        return settings?.spreads == true ? (slots + 1) / 2 : slots
    }

    /// The interior pages a product's PDF holds, compensation blanks included: the count its formulas
    /// and tables read.
    static func interiorPageCount(_ book: Book, plan: PrintPlan) -> Int {
        leaves(book.pages, settings: plan.interiorSettings(for: book), firstPageRight: plan.firstPageRight).count
    }

    /// The exports; the preflight checks what each of them will render.
    enum Profile: Hashable, Sendable {
        case proof, print
        /// A print-service product from the catalog.
        case service(PrintPlan)
    }

    /// Every problem in one list, blockers first, for callers that show a single list.
    static func printWarnings(_ book: Book, profile: Profile = .print, language: String = "en") -> [String] {
        let report = preflight(book, directory: nil, profile: profile)
        return (report.blockers + report.warnings).map { $0.message(language: language) }
    }

    /// A cheap pass over the book that lists everything that would stop the export (text that
    /// does not fit, photos or files that are missing, a LUT that cannot be read) and the print
    /// warnings (resolution, blank pages). Without `directory`, files on disk are not checked.
    static func preflight(_ book: Book, directory: URL?, profile: Profile) -> Preflight {
        let settings: PrintSettings? = switch profile {
        case .proof: nil
        case .print: book.printSettings ?? PrintSettings()
        case let .service(plan): plan.interiorSettings(for: book)
        }
        let plan: PrintPlan? = if case let .service(plan) = profile { plan } else { nil }
        let w = book.format.widthMM * pointsPerMM
        let h = book.format.heightMM * pointsPerMM
        let bleed = (settings?.bleedMM ?? 0) * pointsPerMM
        let ppi = settings?.targetPPI ?? ImageOutput.proof.ppi
        let safe = book.contentInsetPoints
        guard w.isFinite, h.isFinite, min(w,h) > 50, safe >= 0, 2*safe < min(w,h),
              bleed.isFinite, bleed >= 0, ppi.isFinite, ppi > 0 else {
            return Preflight(blockers: [PreflightIssue(problem: .invalidDimensions)])
        }
        var report = Preflight()
        var checkedFiles = Set<String>()
        var checkedLooks = Set<String>()
        let fm = FileManager.default
        /// Where an issue is, so it can be opened: the printed page number, the page and its object.
        struct Place {
            var location: PreflightIssue.Location
            var pageID: UUID?
            var target: IssueTarget?
            var occurrence = 0
            var excerpt: String?

            func issue(_ problem: PreflightIssue.Problem) -> PreflightIssue {
                PreflightIssue(location: location, problem: problem, pageID: pageID, target: target,
                               occurrence: occurrence, excerpt: excerpt)
            }
        }
        func checkFiles(_ photo: BookPhoto, at place: Place) {
            guard let directory else { return }
            if checkedFiles.insert(photo.filename).inserted,
               !fm.fileExists(atPath: BookStorage.assetURL(filename: photo.filename, in: directory).path) {
                report.blockers.append(place.issue(.missingFile(photo.name)))
            }
            let film = book.effectiveFilm(for: photo)
            guard film.preset == .custom, film.strength > 0 else { return }
            let name = film.lutFilename ?? ""
            guard checkedLooks.insert(name).inserted else { return }
            if film.lutFilename.map({ (try? FilmRenderer.validateLUT(at: BookStorage.lutURL(filename: $0, in: directory))) == nil }) ?? true {
                report.blockers.append(place.issue(.unreadableLUT(name.isEmpty ? photo.name : name)))
            }
        }
        func checkResolution(_ photo: BookPhoto, frame: CGRect, fills: Bool, crop: PhotoCrop, at place: Place) {
            guard settings != nil else { return }
            // The same measure as the canvas badge; rounded like the message, so "300 ppi < 300 ppi" cannot appear.
            guard let measured = PhotoResolution.ppi(of: photo, in: frame, fills: fills, crop: crop) else { return }
            let actual = measured.rounded()
            if PhotoResolution.level(measured, target: ppi) != .good {
                report.warnings.append(place.issue(.lowResolution(photo: photo.name, ppi: actual, target: ppi)))
            }
        }

        let slots = leaves(book.pages, settings: settings, firstPageRight: plan?.firstPageRight == true)
        if let plan {
            let product = plan.issues(for: book, interiorPages: slots.count)
            report.blockers += product.blockers
            report.warnings += product.warnings
        }
        let blanks = slots.indices.filter { slots[$0] == nil }.map { $0 + 1 }
        if !blanks.isEmpty, settings != nil {
            report.warnings.append(PreflightIssue(problem: .blankPages(blanks)))
        }
        let style = book.editorialStyle
        for (position, slot) in slots.enumerated() {
            guard let leaf = slot, leaf.half == 0 else { continue }
            // A cancelled live run is discarded, so stop working on it.
            if Task.isCancelled { break }
            let page = leaf.page
            let at = Place(location: .page(leaf.number), pageID: page.id)
            if page.photoIDs.contains(where: { book.photo($0) == nil }) {
                report.blockers.append(at.issue(.missingPhoto))
            }
            let composition = PageComposition(page: page, book: book)
            var placed = [UUID: Int]()
            for slot in composition.photos {
                var place = at
                place.target = .photo(slot.photo.id)
                place.occurrence = placed[slot.photo.id, default: 0]
                placed[slot.photo.id, default: 0] += 1
                checkFiles(slot.photo, at: place)
                checkResolution(slot.photo, frame: slot.frame, fills: slot.fills, crop: slot.crop, at: place)
            }
            for caption in composition.captions where !caption.fits {
                var place = at
                place.target = .caption(caption.photoID)
                place.excerpt = Self.excerpt(of: caption.text.string)
                report.warnings.append(place.issue(.captionDoesNotFit))
            }
            let story = composition.storyDrawingBlocks(page: page, book: book)
            let guides = settings.map { PrintGuides.frames(pageSize: composition.bounds.size, settings: $0) }
            if let guides {
                // The binding edge of a single page is not cut, so it can hold a photo near it.
                // `leaves` puts the first slot on the left, except for a product whose first page is a right page.
                let onRight = plan?.firstPageRight == true ? position.isMultiple(of: 2) : !position.isMultiple(of: 2)
                let bound: Set<PrintGuides.Edge> = page.effectiveLayout == .fullSpread ? []
                    : onRight ? [.left] : [.right]
                var placedAgain = [UUID: Int]()
                for slot in composition.photos {
                    let occurrence = placedAgain[slot.photo.id, default: 0]
                    placedAgain[slot.photo.id, default: 0] += 1
                    guard let nearest = guides.edgesNearTrim(of: slot.frame, ignoring: bound)
                        .min(by: { $0.distanceMM < $1.distanceMM }) else { continue }
                    var place = at
                    place.target = .photo(slot.photo.id)
                    place.occurrence = occurrence
                    report.warnings.append(place.issue(.photoNearEdge(photo: slot.photo.name,
                                                                      distanceMM: nearest.distanceMM)))
                }
                if story.contains(where: { $0.text.length > 0 && !guides.keepsInsideSafe($0.frame) }) {
                    var place = at
                    place.target = .story
                    report.warnings.append(place.issue(.textOutsideSafeMargin))
                }
                for box in composition.textBoxes where !box.text.isEmpty && box.prints(paper: style.paper, ink: style.ink)
                    && !guides.keepsInsideSafe(box.frame.rect(in: composition.bounds)) {
                    var place = at
                    place.target = .textBox(box.id)
                    place.excerpt = Self.excerpt(of: box.text)
                    report.warnings.append(place.issue(.textOutsideSafeMargin))
                }
                // A caption that does not fit is already its own warning.
                for caption in composition.captions where caption.fits && !guides.keepsInsideSafe(caption.frame) {
                    var place = at
                    place.target = .caption(caption.photoID)
                    place.excerpt = Self.excerpt(of: caption.text.string)
                    report.warnings.append(place.issue(.textOutsideSafeMargin))
                }
            }
            if !story.allSatisfy({ $0.text.length == 0 || EditorialTypesetter.fits($0.text, in: $0.frame) }) {
                var place = at
                place.target = .story
                report.blockers.append(place.issue(.textOverflows))
            }
            for box in composition.textBoxes where box.prints(paper: style.paper, ink: style.ink) {
                let frame = box.frame.rect(in: composition.bounds)
                if !EditorialTypesetter.fits(PageComposition.boxText(box: box, book: book),
                                             in: frame.insetBy(dx: box.textInsetPoints, dy: box.textInsetPoints)) {
                    var place = at
                    place.target = .textBox(box.id)
                    place.excerpt = Self.excerpt(of: box.text)
                    report.blockers.append(place.issue(.textOverflows))
                }
            }
        }
        // The cover faces at the size each export draws them: the page for Generic Print, the board of a
        // product's flat cover, the page for a cover printed as the first and last page.
        let faceSize: CGSize?? = switch profile {
        case .proof: nil
        case .print: .some(nil)
        case let .service(plan):
            switch plan.coverKind(for: book) {
            case .none: nil
            case .interiorPages: .some(book.format.pageSize)
            case .flat: .some(plan.coverRules(for: book).panel.map {
                CGSize(width: $0.widthMM.mm * pointsPerMM, height: $0.heightMM.mm * pointsPerMM)
            } ?? book.format.pageSize)
            }
        }
        if let cover = book.cover, let faceSize {
            for (id, front) in [(cover.frontPhotoID, true), (cover.backPhotoID, false)] {
                let place = Place(location: .cover, target: .cover(front: front))
                let face = faceSize.map { BookCoverGeometry(book: book, front: front, size: $0) }
                    ?? BookCoverGeometry(book: book, front: front, bleed: bleed)
                if let frame = face.titleFrame, !EditorialTypesetter.fits(face.title, in: frame) {
                    report.blockers.append(place.issue(.textOverflows))
                }
                guard let id else { continue }
                if let photo = book.photo(id) {
                    checkFiles(photo, at: place)
                    checkResolution(photo, frame: face.photoFrame, fills: face.fills, crop: face.photoCrop, at: place)
                } else {
                    report.blockers.append(place.issue(.missingPhoto))
                }
            }
        }
        return report
    }

    /// The first words of a box's text, short enough for a list row; nil for an empty box.
    private static func excerpt(of text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ")
        guard !words.isEmpty else { return nil }
        return words.count > 28 ? String(words.prefix(28)) + "…" : words
    }

    private struct Leaf {
        let page: BookPage
        let half: Int
        let number: Int
    }

    /// The interior slots in PDF order; nil is a compensation blank. The generic imposition starts with a
    /// left page; `firstPageRight` shifts it by one for products whose first interior page is a right page.
    private static func leaves(_ pages: [BookPage], settings: PrintSettings?, firstPageRight: Bool = false) -> [Leaf?] {
        var leaves = [Leaf?]()
        if settings?.firstPageOnRight == true { leaves.append(nil) }
        // Folios follow the editor's numbering, so blanks added for the imposition are not counted.
        for (page, number) in zip(pages, Book.pageNumbers(of: pages)) {
            if page.effectiveLayout == .fullSpread && settings != nil && !leaves.count.isMultiple(of: 2) {
                leaves.append(nil)
            }
            leaves.append(Leaf(page: page, half: 0, number: number))
            if page.effectiveLayout == .fullSpread {
                leaves.append(Leaf(page: page, half: 1, number: number + 1))
            }
        }
        if settings?.spreads == true && !leaves.count.isMultiple(of: 2) { leaves.append(nil) }
        if firstPageRight {
            // Generic imposition starts at a left slot; this product's first physical interior page is right.
            if settings?.firstPageOnRight == true { leaves.removeFirst() }
            else { leaves.insert(nil, at: 0) }
        }
        return leaves
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: .sRGBSpace, components: [red, green, blue, alpha])!
    }

    private static func box(_ rect: CGRect) -> Data {
        var value = rect
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    /// Resolution and JPEG quality of the photographs embedded in a PDF.
    struct ImageOutput {
        let ppi: Double
        let quality: Double
        /// One export's last developed photograph.
        fileprivate let cache = PaintCache()

        /// The viewing PDF is for screens: about 150 ppi at quality 0.85.
        static var proof: ImageOutput { ImageOutput(ppi: 150, quality: 0.85) }
        static func print(_ settings: PrintSettings) -> ImageOutput { ImageOutput(ppi: settings.targetPPI, quality: 0.95) }
    }

    /// Keeps the last photograph developed and its embedded image, so both halves of a panorama and a
    /// photo repeated on the next page are rendered once and embedded once.
    fileprivate final class PaintCache {
        struct Render: Equatable {
            let filename: String
            let film: FilmSettings
            let adjustments: PhotoAdjustments?
            let maxPixels: Int
        }
        struct Placed: Equatable {
            let render: Render
            let cropped: CGRect
            let area: CGRect
        }
        var render: (key: Render, image: CGImage)?
        var placed: (key: Placed, image: CGImage, placement: CGRect)?
    }

    /// Bleed per edge of an interior page, in points. `inner` is the binding edge.
    private struct PageBleed {
        var top: Double = 0, bottom: Double = 0, outer: Double = 0, inner: Double = 0

        init() {}

        init(uniform value: Double) { (top, bottom, outer, inner) = (value, value, value, value) }

        init(_ edges: PrintProfile.Edges) {
            top = edges.top.mm * BookPDF.pointsPerMM
            bottom = edges.bottom.mm * BookPDF.pointsPerMM
            outer = edges.outer.mm * BookPDF.pointsPerMM
            inner = edges.inner.mm * BookPDF.pointsPerMM
        }

        var all: [Double] { [top, bottom, outer, inner] }
        var largest: Double { all.max() ?? 0 }
    }

    /// A product's flat cover in points: back, hinge, spine, hinge, front, with the wrap and the bleed
    /// beyond it around the trim line.
    private struct FlatCover {
        var panel: CGSize
        var hinge: Double
        var spine: Double
        var wrap: Double
        var bleedTop: Double
        var bleedBottom: Double
        var bleedOuter: Double

        var width: Double { 2 * (panel.width + hinge) + spine }
        var side: Double { wrap + bleedOuter }
        var top: Double { wrap + bleedTop }
        var bottom: Double { wrap + bleedBottom }
    }

    /// What one PDF file holds, in order: a flat cover, the generic cover, the front cover page, the
    /// interior and the back cover page.
    private struct Output {
        /// Nil for the viewing PDF.
        var settings: PrintSettings?
        var bleed = PageBleed()
        /// Generic Print's `Cover.pdf`: the book's cover at the page size, with the uniform bleed.
        var genericCover: BookCover?
        var flatCover: FlatCover?
        /// The front cover as the first page and the back cover as the last, at the page size.
        var coverPages = false
        var interior = true
        /// The first interior page of the PDF is a right page.
        var firstPageRight = false
    }

    /// The margins of the media box around the trim box, in points.
    private struct Insets {
        var left: Double, right: Double, top: Double, bottom: Double
    }

    /// Streams the PDF into a hidden file next to `url` and moves it into place only when it is complete,
    /// so a failed or cancelled export leaves an existing file untouched.
    private static func render(_ book: Book, directory: URL, output: Output, to url: URL,
                               meter: ProgressMeter? = nil) throws {
        let fm = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).pdf")
        defer { try? fm.removeItem(at: temporary) }
        try renderDocument(book, directory: directory, output: output, to: temporary, meter: meter)
        try Task.checkCancellation()
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: url)
        }
    }

    private static func renderDocument(_ book: Book, directory: URL, output: Output, to url: URL,
                                       meter: ProgressMeter?) throws {
        let settings = output.settings
        let w = book.format.widthMM * pointsPerMM
        let h = book.format.heightMM * pointsPerMM
        let bleed = output.bleed
        let safe = book.contentInsetPoints
        let images = settings.map(ImageOutput.print) ?? .proof
        let spine = (output.genericCover?.spineMM ?? 0) * pointsPerMM
        let flatMeasures: [Double] = output.flatCover.map {
            [Double($0.panel.width), Double($0.panel.height), $0.hinge, $0.spine, $0.wrap, $0.bleedTop, $0.bleedBottom,
             $0.bleedOuter]
        } ?? []
        guard w.isFinite, h.isFinite, w > 50, h > 50, !book.pages.isEmpty,
              bleed.all.allSatisfy({ $0.isFinite && $0 >= 0 }), safe >= 0, safe * 2 < min(w,h),
              images.ppi.isFinite, images.ppi > 0, spine.isFinite, spine >= 0,
              flatMeasures.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw ExportError.invalidBook }
        var media = CGRect(x: 0, y: 0, width: w + bleed.largest * 2, height: h + bleed.largest * 2)
        var metadata: [String: Any] = [kCGPDFContextTitle as String: book.title]
        if settings != nil {
            // Quartz uses GTS_PDFX for the output-intent dictionary. The profile describes the
            // exchange RGB space; this exporter does not certify PDF/X or a press condition.
            metadata[kCGPDFContextOutputIntent as String] = [
                kCGPDFXOutputIntentSubtype as String: "GTS_PDFX",
                kCGPDFXOutputConditionIdentifier as String: "sRGB IEC61966-2.1",
                kCGPDFXInfo as String: "sRGB photographic exchange",
                kCGPDFXDestinationOutputProfile as String: CGColorSpace.sRGBSpace
            ] as [String: Any]
        }
        guard let ctx = CGContext(url as CFURL, mediaBox: &media, metadata as CFDictionary)
        else { throw ExportError.invalidBook }
        // Close the file even when a page throws, so the temporary file can be removed.
        var closed = false
        defer { if !closed { ctx.closePDF() } }
        func begin(width: Double, height: Double, insets: Insets) {
            let trim = CGRect(x: insets.left, y: insets.bottom, width: width, height: height)
            // Equal margins are added as twice the margin, so a uniform bleed gives the same boxes as before.
            let full = CGRect(x: trim.minX - insets.left, y: trim.minY - insets.bottom,
                              width: width + (insets.left == insets.right ? 2 * insets.left : insets.left + insets.right),
                              height: height + (insets.top == insets.bottom ? 2 * insets.top : insets.top + insets.bottom))
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: box(full), kCGPDFContextTrimBox as String: box(trim),
                              kCGPDFContextBleedBox as String: box(full)] as CFDictionary)
            ctx.translateBy(x: insets.left, y: insets.bottom + height)
            ctx.scaleBy(x: 1, y: -1)
        }
        func uniform(_ value: Double) -> Insets { Insets(left: value, right: value, top: value, bottom: value) }
        /// A single page's insets: the binding edge is on the left of a right page.
        func pageInsets(right: Bool) -> Insets {
            Insets(left: right ? bleed.inner : bleed.outer, right: right ? bleed.outer : bleed.inner,
                   top: bleed.top, bottom: bleed.bottom)
        }
        if let flat = output.flatCover {
            let panelW = flat.panel.width
            let panelH = flat.panel.height
            let width = flat.width
            begin(width: width, height: panelH, insets: Insets(left: flat.side, right: flat.side, top: flat.top,
                                                               bottom: flat.bottom))
            ctx.setFillColor(EditorialStyle.color(BookCoverGeometry(book: book, front: false).background))
            ctx.fill(CGRect(x: -flat.side, y: -flat.top, width: width + 2 * flat.side,
                            height: panelH + (flat.top == flat.bottom ? 2 * flat.top : flat.top + flat.bottom)))
            drawSpine(book, in: CGRect(x: panelW + flat.hinge, y: 0, width: flat.spine, height: panelH), context: ctx)
            for front in [false, true] {
                // The faces are laid out on the real board, so the title is fitted where it is drawn.
                let face = BookCoverGeometry(book: book, front: front, size: CGSize(width: panelW, height: panelH))
                let outer = CGRect(x: front ? -flat.hinge : -flat.side, y: -flat.top,
                                   width: panelW + flat.hinge + flat.side,
                                   height: panelH + (flat.top == flat.bottom ? 2 * flat.top : flat.top + flat.bottom))
                ctx.saveGState()
                if front { ctx.translateBy(x: width - panelW, y: 0) }
                try drawFace(face, photoID: front ? book.cover?.frontPhotoID : book.cover?.backPhotoID,
                             images: images, book: book, directory: directory, context: ctx, outer: outer)
                ctx.restoreGState()
            }
            ctx.endPDFPage()
            meter?.sheetDone()
        }
        if let cover = output.genericCover {
            let bleed = bleed.outer
            begin(width: 2 * w + spine, height: h, insets: uniform(bleed))
            let spread = CGRect(x: 0, y: 0, width: 2 * w + spine, height: h)
            let back = BookCoverGeometry(book: book, front: false, bleed: bleed)
            ctx.setFillColor(EditorialStyle.color(back.background))
            ctx.fill(spread.insetBy(dx: -bleed, dy: -bleed))
            let backOuter = CGRect(x: -bleed, y: -bleed, width: w + bleed, height: h + 2 * bleed)
            try drawFace(back, photoID: cover.backPhotoID, images: images, book: book, directory: directory, context: ctx,
                         outer: backOuter)
            drawSpine(book, in: CGRect(x: w, y: 0, width: spine, height: h), context: ctx)
            ctx.translateBy(x: w + spine, y: 0)
            let front = BookCoverGeometry(book: book, front: true, bleed: bleed)
            let frontOuter = CGRect(x: 0, y: -bleed, width: w + bleed, height: h + 2 * bleed)
            try drawFace(front, photoID: cover.frontPhotoID, images: images, book: book, directory: directory, context: ctx,
                         outer: frontOuter)
            ctx.endPDFPage()
            meter?.sheetDone()
        }
        /// A cover face printed as a page of the interior file: the front is a right page, the back a left one.
        func coverPage(front: Bool) throws {
            let insets = pageInsets(right: front)
            begin(width: w, height: h, insets: insets)
            let face = BookCoverGeometry(book: book, front: front, size: CGSize(width: w, height: h))
            let outer = CGRect(x: -insets.left, y: -insets.top, width: w + insets.left + insets.right,
                               height: h + insets.top + insets.bottom)
            ctx.setFillColor(EditorialStyle.color(face.background))
            ctx.fill(outer)
            try drawFace(face, photoID: front ? book.cover?.frontPhotoID : book.cover?.backPhotoID,
                         images: images, book: book, directory: directory, context: ctx, outer: outer)
            ctx.endPDFPage()
            meter?.sheetDone()
        }
        if output.coverPages { try coverPage(front: true) }
        if output.interior {
            let slots = leaves(book.pages, settings: settings, firstPageRight: output.firstPageRight)
            let size = settings?.spreads == true ? 2 : 1
            for first in stride(from: 0, to: slots.count, by: size) {
                let sheet = slots[first..<(first + size)]
                try Task.checkCancellation()
                let insets = size == 2
                    ? Insets(left: bleed.outer, right: bleed.outer, top: bleed.top, bottom: bleed.bottom)
                    : pageInsets(right: !(first + (output.firstPageRight ? 1 : 0)).isMultiple(of: 2))
                begin(width: Double(sheet.count)*w, height: h, insets: insets)
                try autoreleasepool {
                    for (index,slot) in sheet.enumerated() {
                        ctx.saveGState()
                        defer { ctx.restoreGState() }
                        ctx.translateBy(x: Double(index)*w, y: 0)
                        let left = index == 0 ? insets.left : 0
                        let right = index == sheet.count-1 ? insets.right : 0
                        let leafArea = CGRect(x: -left, y: -insets.top, width: w+left+right,
                                              height: h + (insets.top == insets.bottom ? 2 * insets.top
                                                                                       : insets.top + insets.bottom))
                        guard let leaf = slot else {
                            // A compensation blank is still a page of the book: print it on the template's paper.
                            ctx.setFillColor(EditorialStyle.color(book.editorialStyle.paper))
                            ctx.fill(leafArea)
                            continue
                        }
                        ctx.clip(to: leafArea)
                        ctx.translateBy(x: -Double(leaf.half)*w, y: 0)
                        // Drawn with the largest bleed and clipped to this page's own edges.
                        try draw(leaf.page, pageNumber: leaf.number, book: book, directory: directory,
                                 context: ctx, bleed: bleed.largest, images: images)
                    }
                }
                ctx.endPDFPage()
                meter?.sheetDone()
            }
        }
        if output.coverPages { try coverPage(front: false) }
        ctx.closePDF()
        closed = true
    }

    private static func draw(_ page: BookPage, pageNumber: Int, book: Book, directory: URL,
                             context: CGContext, bleed: Double, images: ImageOutput) throws {
        // Frames stay at the editor's size; photos reaching the trim are carried into the bleed by paint.
        let composition = PageComposition(page: page, book: book)
        let style = book.editorialStyle
        context.setFillColor(EditorialStyle.color(style.paper))
        context.fill(composition.bounds.insetBy(dx: -bleed, dy: -bleed))
        if let rule = composition.rule {
            context.setFillColor(EditorialStyle.color(style.accent))
            context.fill(rule)
        }
        if let missing = page.photoIDs.first(where: { book.photo($0) == nil }) {
            throw ExportError.missingImage(missing.uuidString)
        }
        let stitchedSlots = page.arrangement.map { $0.isFullBleed && $0.photoCapacity == composition.photos.count } == true
            && page.photoPlacements?.values.contains(where: { $0.frame != nil }) != true
            && composition.captionBand == 0
        let storyBlocks = composition.storyDrawingBlocks(page: page, book: book)
        let backgrounds = composition.storyBackgroundFrames(page: page, blocks: storyBlocks)
        for layer in composition.layers {
            switch layer {
            case let .photo(id):
                guard let index = composition.photos.firstIndex(where: { $0.id == id }) else { continue }
                let slot = composition.photos[index]
                // A photo slips under the neighbors painted after it, whatever the slot order.
                let underlap = stitchedSlots ? tileUnderlap(at: index, in: composition.arrangementPhotoSlots) {
                    composition.rank(.photo(composition.photos[$0].id)) > composition.rank(layer)
                } : Underlap()
                try paint(slot.photo, rect: slot.frame, fills: slot.fills, crop: slot.crop, images: images,
                          book: book, directory: directory, context: context, underlap: underlap,
                          trim: composition.bounds, outer: composition.bounds.insetBy(dx: -bleed, dy: -bleed))
                if let caption = composition.caption(for: id) {
                    drawCaption(caption, style: style, trim: composition.bounds,
                                outer: composition.bounds.insetBy(dx: -bleed, dy: -bleed), context: context)
                }
            case .story:
                if !backgrounds.isEmpty {
                    context.saveGState()
                    context.setAlpha(style.overlayOpacity)
                    context.setFillColor(EditorialStyle.color(style.overlayPaper))
                    context.addRects(backgrounds)
                    context.fillPath()
                    context.restoreGState()
                    context.setFillColor(EditorialStyle.color(style.overlayAccent))
                    context.addRects(backgrounds.compactMap { style.overlayMark(in: $0) })
                    context.fillPath()
                }
                for block in storyBlocks where block.text.length > 0 {
                    try drawText(block.text, in: block.frame, overflow: .textOverflow(pageNumber), context: context)
                }
            case let .textBox(id):
                guard let box = composition.textBoxes.first(where: { $0.id == id }),
                      box.prints(paper: style.paper, ink: style.ink) else { continue }
                let frame = box.frame.rect(in: composition.bounds)
                if let fill = box.printedFill(paper: style.paper) {
                    context.setFillColor(EditorialStyle.color(fill))
                    context.fill(frame)
                }
                if let border = box.border(ink: style.ink) {
                    context.setStrokeColor(EditorialStyle.color(border.color))
                    context.setLineWidth(border.width)
                    context.stroke(frame.insetBy(dx: border.width / 2, dy: border.width / 2))
                }
                let textFrame = frame.insetBy(dx: box.textInsetPoints, dy: box.textInsetPoints)
                try drawText(PageComposition.boxText(box: box, book: book),
                             in: textFrame, overflow: .textOverflow(pageNumber), context: context)
            }
        }
        if let folio = composition.folio {
            _ = EditorialTypesetter.draw(style.typography(String(pageNumber), heading: nil, mixed: false),
                                         in: folio, context: context)
        }
    }

    /// A caption belongs to its photo's layer. Its band takes the template's panel for text over a photo
    /// and, where it reaches the trim, continues into the bleed like the photo under it.
    static func drawCaption(_ caption: PageComposition.Caption, style: EditorialStyle, trim: CGRect, outer: CGRect,
                            context: CGContext) {
        if let band = caption.band {
            context.saveGState()
            context.setAlpha(style.overlayOpacity)
            context.setFillColor(EditorialStyle.color(style.overlayPaper))
            context.fill(bleedArea(of: band, trim: trim, outer: outer))
            context.restoreGState()
        }
        // The frame is as tall as the text needs, so nothing is cut; a caption that does not fit is an issue.
        EditorialTypesetter.draw(caption.text, in: caption.frame, context: context)
    }

    /// How far a photo extends under each neighbor painted after it.
    private struct Underlap: Equatable {
        var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
    }

    private static func tileUnderlap(at index: Int, in slots: [CGRect], paintedLater: (Int) -> Bool) -> Underlap {
        let frame = slots[index]
        let later = slots.indices.filter { $0 != index && paintedLater($0) }.map { slots[$0] }
        let tolerance: CGFloat = 0.000001
        func overlapsVertically(_ other: CGRect) -> Bool {
            other.maxY > frame.minY + tolerance && other.minY < frame.maxY - tolerance
        }
        func overlapsHorizontally(_ other: CGRect) -> Bool {
            other.maxX > frame.minX + tolerance && other.minX < frame.maxX - tolerance
        }
        // Cover the reader's independently antialiased photo edges, including at thumbnail scale.
        let reach: CGFloat = 7
        return Underlap(
            top: later.contains { abs($0.maxY - frame.minY) < tolerance && overlapsHorizontally($0) } ? reach : 0,
            left: later.contains { abs($0.maxX - frame.minX) < tolerance && overlapsVertically($0) } ? reach : 0,
            bottom: later.contains { abs($0.minY - frame.maxY) < tolerance && overlapsHorizontally($0) } ? reach : 0,
            right: later.contains { abs($0.minX - frame.maxX) < tolerance && overlapsVertically($0) } ? reach : 0)
    }

    private static func paint(_ photo: BookPhoto, rect: CGRect, fills: Bool, crop: PhotoCrop, images: ImageOutput,
                              book: Book, directory: URL, context: CGContext, underlap: Underlap = Underlap(),
                              trim: CGRect, outer: CGRect) throws {
        guard !rect.isEmpty else { return }
        let source = BookStorage.assetURL(filename: photo.filename, in: directory)
        let settings = book.effectiveFilm(for: photo)
        let lut = settings.lutFilename.map { BookStorage.lutURL(filename: $0, in: directory) }
        let pixels = CGSize(width: max(1, photo.pixelWidth), height: max(1, photo.pixelHeight))
        let cropped = crop.imageRect(for: pixels, in: rect, fills: fills)
        let desired = ceil(max(cropped.width, cropped.height) * images.ppi / 72)
        let maxPixels = Int(min(max(pixels.width, pixels.height), max(1, desired)))
        let area = fills ? bleedArea(of: rect, trim: trim, outer: outer) : rect
        let cache = images.cache
        let renderKey = PaintCache.Render(filename: photo.filename, film: settings, adjustments: photo.adjustments,
                                          maxPixels: maxPixels)
        let placedKey = PaintCache.Placed(render: renderKey, cropped: cropped, area: area)
        let image: CGImage
        let placement: CGRect
        if let placed = cache.placed, placed.key == placedKey {
            (image, placement) = (placed.image, placed.placement)
        } else {
            let rendered: CGImage
            if let last = cache.render, last.key == renderKey {
                rendered = last.image
            } else {
                guard let developed = FilmRenderer.image(from: source, maxPixelSize: maxPixels, settings: settings,
                                                         lutURL: lut, adjustments: photo.adjustments)
                else { throw ExportError.missingImage(photo.name) }
                rendered = developed
                cache.render = (renderKey, developed)
            }
            let padded: CGImage
            (padded, placement) = mirrorPadded(rendered, placement: cropped, toCover: area)
            image = jpegBacked(padded, quality: images.quality)
            cache.placed = (placedKey, image, placement)
        }
        if underlap != Underlap() {
            // The seams run through the bleed too, where the neighbors are also carried out.
            let reach = CGRect(x: area.minX - underlap.left, y: area.minY - underlap.top,
                               width: area.width + underlap.left + underlap.right,
                               height: area.height + underlap.top + underlap.bottom)
            let seams = CGMutablePath()
            if underlap.left > 0 {
                seams.addRect(CGRect(x: reach.minX, y: reach.minY, width: 2 * underlap.left, height: reach.height))
            }
            if underlap.right > 0 {
                seams.addRect(CGRect(x: reach.maxX - 2 * underlap.right, y: reach.minY, width: 2 * underlap.right,
                                     height: reach.height))
            }
            if underlap.top > 0 {
                seams.addRect(CGRect(x: reach.minX, y: reach.minY, width: reach.width, height: 2 * underlap.top))
            }
            if underlap.bottom > 0 {
                seams.addRect(CGRect(x: reach.minX, y: reach.maxY - 2 * underlap.bottom, width: reach.width,
                                     height: 2 * underlap.bottom))
            }
            let extended = placement.union(reach)
            context.saveGState()
            context.addPath(seams)
            context.clip()
            drawImage(image, at: extended, in: context)
            context.restoreGState()
        }
        context.saveGState()
        context.clip(to: area)
        drawImage(image, at: placement, in: context)
        context.restoreGState()
    }

    /// The area a photo prints in: its frame, carried out to `outer` on every side where it reaches `trim`.
    /// The crop is computed for the frame alone, so the photo inside the trim matches the editor.
    static func bleedArea(of frame: CGRect, trim: CGRect, outer: CGRect) -> CGRect {
        let tolerance: CGFloat = 0.01
        let minX = frame.minX <= trim.minX + tolerance ? min(frame.minX, outer.minX) : frame.minX
        let minY = frame.minY <= trim.minY + tolerance ? min(frame.minY, outer.minY) : frame.minY
        let maxX = frame.maxX >= trim.maxX - tolerance ? max(frame.maxX, outer.maxX) : frame.maxX
        let maxY = frame.maxY >= trim.maxY - tolerance ? max(frame.maxY, outer.maxY) : frame.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Where the crop leaves no spare image for the bleed, extends the image by reflecting it at its own edge.
    /// The reflection is built in pixels, so the print shows no seam where it meets the photograph.
    private static func mirrorPadded(_ image: CGImage, placement: CGRect, toCover area: CGRect) -> (CGImage, CGRect) {
        guard !placement.isEmpty, image.width > 0, image.height > 0 else { return (image, placement) }
        let w = image.width, h = image.height
        let scaleX = CGFloat(w) / placement.width, scaleY = CGFloat(h) / placement.height
        func pad(_ points: CGFloat, _ scale: CGFloat, _ limit: Int) -> Int {
            points > 0.001 ? min(limit, Int(ceil(points * scale)) + 1) : 0
        }
        let left = pad(placement.minX - area.minX, scaleX, w), right = pad(area.maxX - placement.maxX, scaleX, w)
        let top = pad(placement.minY - area.minY, scaleY, h), bottom = pad(area.maxY - placement.maxY, scaleY, h)
        guard left + right + top + bottom > 0,
              let context = CGContext(data: nil, width: w + left + right, height: h + top + bottom, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: .sRGBSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (image, placement) }
        context.interpolationQuality = .none
        // Bitmap rows run bottom up: the page's bottom padding is at y = 0.
        let xs: [(axis: CGFloat?, used: Bool)] = [(CGFloat(left), left > 0), (nil, true), (CGFloat(left + w), right > 0)]
        let ys: [(axis: CGFloat?, used: Bool)] = [(CGFloat(bottom), bottom > 0), (nil, true), (CGFloat(bottom + h), top > 0)]
        for x in xs where x.used {
            for y in ys where y.used {
                context.saveGState()
                if let axis = x.axis {
                    context.translateBy(x: 2 * axis, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                if let axis = y.axis {
                    context.translateBy(x: 0, y: 2 * axis)
                    context.scaleBy(x: 1, y: -1)
                }
                context.draw(image, in: CGRect(x: left, y: bottom, width: w, height: h))
                context.restoreGState()
            }
        }
        guard let padded = context.makeImage() else { return (image, placement) }
        return (padded, CGRect(x: placement.minX - CGFloat(left) / scaleX, y: placement.minY - CGFloat(top) / scaleY,
                               width: CGFloat(padded.width) / scaleX, height: CGFloat(padded.height) / scaleY))
    }

    /// Re-encodes a render as JPEG. Quartz embeds a JPEG-backed image as DCT data, so a page of
    /// photographs costs a few megabytes instead of the lossless pixels.
    private static func jpegBacked(_ image: CGImage, quality: Double) -> CGImage {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return image }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: data),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                 intent: .defaultIntent)
        else { return image }
        return jpeg
    }

    private static func drawImage(_ image: CGImage, at placement: CGRect, in context: CGContext) {
        context.translateBy(x: placement.minX, y: placement.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: placement.size))
    }

    private static func drawFace(_ face: BookCoverGeometry, photoID: UUID?, images: ImageOutput, book: Book,
                                 directory: URL, context: CGContext, outer: CGRect) throws {
        if let id = photoID {
            guard let photo = book.photo(id) else { throw ExportError.missingImage(id.uuidString) }
            context.saveGState()
            defer { context.restoreGState() }
            context.clip(to: outer)
            try paint(photo, rect: face.photoFrame, fills: face.fills, crop: face.photoCrop, images: images,
                      book: book, directory: directory, context: context, trim: face.bounds, outer: outer)
        }
        // A band or rule that reaches the trim continues into the bleed, wrap and hinge like the photo.
        if let band = face.band {
            context.setFillColor(color(0.97, 0.97, 0.97, alpha: 0.94))
            context.fill(bleedArea(of: band, trim: face.bounds, outer: outer))
        }
        if let rule = face.rule {
            context.setFillColor(EditorialStyle.color(book.editorialStyle.accent))
            context.fill(bleedArea(of: rule, trim: face.bounds, outer: outer))
        }
        if let rect = face.titleFrame {
            try drawText(face.title, in: rect, overflow: .coverTextOverflow, context: context)
        }
    }

    /// The title runs top to bottom on spines of at least 5 mm, with its tops toward the front cover.
    static func spineTitle(_ book: Book, spineWidth: CGFloat) -> NSAttributedString? {
        let text = (book.cover?.title ?? book.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, spineWidth >= 5 * pointsPerMM else { return nil }
        let style = book.editorialStyle
        let size = min(spineWidth * 0.48, 13)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let ink: UInt32 = book.template == nil ? 0xF2F2F2 : style.titleInk
        return NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(style.titleFont as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): EditorialStyle.color(ink),
            .paragraphStyle: paragraph,
        ])
    }

    private static func drawSpine(_ book: Book, in spine: CGRect, context: CGContext) {
        guard let title = spineTitle(book, spineWidth: spine.width) else { return }
        let margin = min(spine.height * 0.08, 18 * pointsPerMM)
        let length = spine.height - 2 * margin
        let height = min(spine.width, EditorialTypesetter.requiredHeight(title, width: .greatestFiniteMagnitude))
        context.saveGState()
        context.translateBy(x: spine.midX, y: spine.minY + margin)
        context.rotate(by: .pi / 2)
        EditorialTypesetter.draw(title, in: CGRect(x: 0, y: -height / 2, width: length, height: height), context: context)
        context.restoreGState()
    }

    private static func drawText(_ text: NSAttributedString, in rect: CGRect, overflow: ExportError,
                                 context: CGContext) throws {
        if !EditorialTypesetter.draw(text, in: rect, context: context) { throw overflow }
    }
}
