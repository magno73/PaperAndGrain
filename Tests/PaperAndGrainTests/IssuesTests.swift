import XCTest
@testable import PaperAndGrain

/// A lock-protected counter and a gate that holds the monitor's quiet period until the test opens it.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var runs = 0

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen { lock.unlock(); continuation.resume() } else { waiters.append(continuation); lock.unlock() }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let all = waiters
        waiters = []
        lock.unlock()
        all.forEach { $0.resume() }
    }

    func countRun() { lock.lock(); runs += 1; lock.unlock() }
    var runCount: Int { lock.lock(); defer { lock.unlock() }; return runs }
}

@MainActor
final class IssuesTests: XCTestCase {
    typealias Issue = BookPDF.PreflightIssue

    private func lowPhoto(_ name: String, side: Int = 2400) -> BookPhoto {
        BookPhoto(name: name, filename: name, pixelWidth: side, pixelHeight: side)
    }

    private func sampleBook() -> Book {
        let low = lowPhoto("low.png")
        let fine = lowPhoto("fine.png", side: 4000)
        let box = PageTextBox(text: String(repeating: "Troppo testo ", count: 400),
                              frame: PageRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1))
        var book = Book(title: "Issues", photos: [low, fine], pages: [
            BookPage(layout: .fullPage, photoIDs: [fine.id], arrangement: .fullBleed),
            BookPage(layout: .fullPage, photoIDs: [low.id], arrangement: .fullBleed),
            BookPage(layout: .text, text: "Breve", textBoxes: [box]),
            BookPage(layout: .gallery, photoIDs: [UUID()]),
        ])
        book.printSettings = PrintSettings(targetPPI: 300)
        return book
    }

    func testIssueIdsAreStableAndUnique() {
        let book = sampleBook()
        let first = BookPDF.preflight(book, directory: nil, profile: .print)
        let second = BookPDF.preflight(book, directory: nil, profile: .print)
        XCTAssertEqual(first, second)
        let ids = (first.blockers + first.warnings).map(\.id)
        XCTAssertEqual(ids, (second.blockers + second.warnings).map(\.id))
        XCTAssertEqual(Set(ids).count, ids.count, "\(ids)")
        XCTAssertFalse(ids.isEmpty)
        // The id follows the page and the object, not the printed number.
        var shifted = book
        shifted.pages.insert(BookPage(layout: .text, text: "Nuova"), at: 0)
        let after = BookPDF.preflight(shifted, directory: nil, profile: .print)
        XCTAssertEqual(Set(after.blockers.map(\.id)), Set(first.blockers.map(\.id)))
    }

    func testTargetsResolveToTheirPage() throws {
        let book = sampleBook()
        let report = BookPDF.preflight(book, directory: nil, profile: .print)
        let low = try XCTUnwrap(report.warnings.first { if case .lowResolution = $0.problem { true } else { false } })
        XCTAssertEqual(low.target, .photo(book.photos[0].id))
        XCTAssertEqual(low.destination(in: book), .page(book.pages[1].id))
        let overflow = try XCTUnwrap(report.blockers.first { $0.problem == .textOverflows })
        XCTAssertEqual(overflow.target, .textBox(book.pages[2].textBoxes![0].id))
        XCTAssertEqual(overflow.destination(in: book), .page(book.pages[2].id))
        let missing = try XCTUnwrap(report.blockers.first { $0.problem == .missingPhoto })
        XCTAssertEqual(missing.destination(in: book), .page(book.pages[3].id))

        // Without the page id, the object still finds its page; a story and a caption need the id.
        XCTAssertEqual(Issue(problem: .textOverflows, target: .textBox(book.pages[2].textBoxes![0].id)).destination(in: book),
                       .page(book.pages[2].id))
        XCTAssertEqual(Issue(problem: .textOverflows, target: .photo(book.photos[1].id)).destination(in: book),
                       .page(book.pages[0].id))
        XCTAssertEqual(Issue(problem: .textOverflows, pageID: book.pages[1].id, target: .story).destination(in: book),
                       .page(book.pages[1].id))
        XCTAssertEqual(Issue(problem: .textOverflows, pageID: book.pages[1].id, target: .caption(book.photos[0].id)).destination(in: book),
                       .page(book.pages[1].id))
        XCTAssertEqual(Issue(location: .cover, problem: .missingPhoto, target: .cover(front: false)).destination(in: book),
                       .cover(front: false))
        XCTAssertNil(Issue(problem: .textOverflows, pageID: UUID(), target: .story).destination(in: book))
        XCTAssertNil(Issue(problem: .blankPages([1])).destination(in: book))
    }

    func testOverflowIsReportedPerObjectAndClearsWhenShortened() throws {
        var book = sampleBook()
        var report = BookPDF.preflight(book, directory: nil, profile: .print)
        XCTAssertEqual(report.blockers.filter { $0.problem == .textOverflows }.count, 1)
        book.pages[2].textBoxes![0].text = "Breve"
        report = BookPDF.preflight(book, directory: nil, profile: .print)
        XCTAssertTrue(report.blockers.filter { $0.problem == .textOverflows }.isEmpty)

        // A story that overflows is a blocker whose target is the story.
        book.pages[2].text = String(repeating: "Una riga di racconto che non finisce mai. ", count: 400)
        report = BookPDF.preflight(book, directory: nil, profile: .print)
        let story = try XCTUnwrap(report.blockers.first { $0.problem == .textOverflows })
        XCTAssertEqual(story.target, .story)
        XCTAssertEqual(story.pageID, book.pages[2].id)
    }

    func testPhotoBelowTheTargetRaisesAWarningOnThatPhoto() throws {
        var book = sampleBook()
        book.photos[0].pixelWidth = 4000
        book.photos[0].pixelHeight = 4000
        XCTAssertTrue(BookPDF.preflight(book, directory: nil, profile: .print).warnings.isEmpty)
        book.photos[0].pixelWidth = 1000
        book.photos[0].pixelHeight = 1000
        let warnings = BookPDF.preflight(book, directory: nil, profile: .print).warnings
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings.first?.target, .photo(book.photos[0].id))
    }

    func testGroupsFollowBookOrderWithTheCoverLast() {
        let id = UUID()
        let issues = [
            Issue(location: .cover, problem: .textOverflows, target: .cover(front: true)),
            Issue(location: .page(3), problem: .missingPhoto, pageID: id),
            Issue(problem: .blankPages([2])),
            Issue(location: .page(1), problem: .textOverflows, pageID: UUID(), target: .story),
            Issue(location: .page(3), problem: .textOverflows, pageID: id, target: .story),
        ]
        let groups = BookPDF.IssueGroup.groups(issues)
        XCTAssertEqual(groups.map(\.id), ["book", "page:1", "page:3", "cover"])
        XCTAssertEqual(groups[2].issues.map(\.problem), [.missingPhoto, .textOverflows])
        let report = BookPDF.Preflight(blockers: issues, warnings: [])
        XCTAssertEqual(report.groups(of: .blocker), groups)
        XCTAssertTrue(report.groups(of: .warning).isEmpty)
    }

    func testPlacelessMessageLeavesOutThePage() {
        let issue = Issue(location: .page(2), problem: .missingFile("a.png"))
        XCTAssertEqual(issue.message(language: "en"), "p. 2 · a.png · Photo file missing")
        XCTAssertEqual(issue.message(language: "en", includingPlace: false), "a.png · Photo file missing")
    }

    // MARK: Live monitor

    private func report(for book: Book) -> BookPDF.Preflight {
        BookPDF.Preflight(blockers: [Issue(problem: .blankPages([book.pages.count]))])
    }

    func testOnlyTheLastChangeOfAPauseRunsTheCheck() async {
        let gate = Gate()
        let monitor = IssueMonitor(sleep: { _ in await gate.wait() }, check: { book, _, _ in
            gate.countRun()
            return BookPDF.Preflight(blockers: [Issue(problem: .blankPages([book.pages.count]))])
        })
        var book = Book(title: "Typing")
        for count in 1...6 {
            book.pages = Array(repeating: BookPage(layout: .text), count: count)
            monitor.bookChanged(book, directory: nil)
        }
        XCTAssertNil(monitor.report)
        gate.open()
        await monitor.settle()
        XCTAssertEqual(gate.runCount, 1, "one run for six keystrokes")
        XCTAssertEqual(monitor.report?.blockers.first?.problem, .blankPages([6]))
    }

    func testTheFirstLookDoesNotWait() async {
        let gate = Gate()
        let monitor = IssueMonitor(sleep: { _ in await gate.wait() }, check: { _, _, _ in BookPDF.Preflight() })
        monitor.bookChanged(Book(title: "Open"), directory: nil, immediately: true)
        await monitor.settle()
        XCTAssertEqual(monitor.report, BookPDF.Preflight())
    }

    func testARunOvertakenByAChangeNeverPublishes() async throws {
        let release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "the slow run ends")
        let monitor = IssueMonitor(sleep: { _ in }, check: { book, _, _ in
            if book.title == "slow" {
                release.wait()
                finished.fulfill()
            }
            return BookPDF.Preflight(blockers: [Issue(problem: .blankPages([book.title.count]))])
        })
        monitor.bookChanged(Book(title: "slow"), directory: nil, immediately: true)
        try await Task.sleep(for: .milliseconds(50))
        monitor.bookChanged(Book(title: "new"), directory: nil, immediately: true)
        await monitor.settle()
        XCTAssertEqual(monitor.report?.blockers.first?.problem, .blankPages([3]))
        release.signal()
        await fulfillment(of: [finished], timeout: 5)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.report?.blockers.first?.problem, .blankPages([3]), "the slow run was cancelled")
    }

    func testStopCancelsThePendingRun() async throws {
        let gate = Gate()
        let monitor = IssueMonitor(sleep: { _ in await gate.wait() }, check: { _, _, _ in
            gate.countRun()
            return BookPDF.Preflight()
        })
        monitor.bookChanged(Book(title: "Closing"), directory: nil)
        monitor.stop()
        gate.open()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(gate.runCount, 0)
        XCTAssertNil(monitor.report)
    }


    func testEveryProblemKindHasAnIconAndADistinctKind() {
        // The kinds are an exhaustive switch (`Problem.kind`, `symbol`, `message`, the editor's fix):
        // each one has a distinct kind and an icon.
        let all: [Issue.Problem] = [.invalidDimensions, .missingPhoto, .missingFile("a"), .unreadableLUT("a"),
                                    .lowResolution(photo: "a", ppi: 1, target: 2), .textOverflows, .blankPages([1])]
        XCTAssertEqual(Set(all.map(\.kind)).count, all.count)
        XCTAssertTrue(all.allSatisfy { !$0.symbol.isEmpty })
    }

    /// Timing of the live check on a real package. Set `PAPERGRAIN_PREFLIGHT_BOOK` to a book built
    /// with `cli build` (the status document records the 50-page, 150-photo case); it is skipped otherwise.
    /// For a release build: `swift test -c release -Xswiftc -enable-testing --filter testPreflightTiming`.
    func testPreflightTimingOnAPackage() throws {
        guard let path = ProcessInfo.processInfo.environment["PAPERGRAIN_PREFLIGHT_BOOK"] else {
            throw XCTSkip("PAPERGRAIN_PREFLIGHT_BOOK is not set")
        }
        let directory = URL(fileURLWithPath: path)
        let book = try BookStorage.read(from: directory)
        var milliseconds = [Double]()
        for _ in 0..<21 {
            let start = ContinuousClock.now
            let report = BookPDF.preflight(book, directory: directory, profile: .print)
            let elapsed = ContinuousClock.now - start
            milliseconds.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
            XCTAssertNotNil(report)
        }
        let cold = milliseconds[0]
        let warm = milliseconds.dropFirst().sorted()
        print("PREFLIGHT pages=\(book.pages.count) photos=\(book.photos.count) cold=\(String(format: "%.1f", cold)) ms "
              + "median=\(String(format: "%.1f", warm[warm.count / 2])) ms max=\(String(format: "%.1f", warm.last!)) ms")
    }
}
