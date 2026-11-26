import Foundation
import XCTest
@testable import PaperAndGrain

/// A checker that knows which words are wrong and how often it was asked.
@MainActor
private final class FakeChecker: SpellChecking {
    private var calls: [String] = []
    private var learned: Set<String> = []
    let wrong: Set<String>

    init(wrong: Set<String>) { self.wrong = wrong }

    var asked: [String] { calls }

    func misspellings(in text: String) -> [NSRange] {
        calls.append(text)
        var found: [NSRange] = []
        let string = text as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byWords) { word, range, _, _ in
            if let word, self.wrong.contains(word.lowercased()) { found.append(range) }
        }
        return found
    }

    func hasLearned(_ word: String) -> Bool { learned.contains(word.lowercased()) }
    func learn(_ word: String) { learned.insert(word.lowercased()) }
}

@MainActor
final class SpellingTests: XCTestCase {
    private func words(_ issues: [BookPDF.PreflightIssue]) -> [String] {
        issues.compactMap { if case let .possibleMisspelling(word, _) = $0.problem { word } else { nil } }
    }

    private func book() -> (Book, BookPhoto) {
        var photo = BookPhoto(name: "a.jpg", filename: "a.jpg", pixelWidth: 4, pixelHeight: 3)
        photo.caption = "Tramonto a Swakopmund con un cielo sbagliatto"
        photo.location = PhotoLocation(name: "Swakopmund", latitude: -22.6, longitude: 14.5)
        let box = PageTextBox(text: "Seen at the markett in Windhoek", frame: PageRect(x: 0.1, y: 0.1, width: 0.4, height: 0.2))
        var page = BookPage(photoIDs: [photo.id], text: "Una giornata bellisima nel deserto", heading: "Namibia")
        page.textBoxes = [box]
        var book = Book(title: "Namibia", photos: [photo], pages: [page])
        book.cover = BookCover(title: "Namibia", backText: "Grazie per aver viaggiatto con noi")
        return (book, photo)
    }

    private let wrong: Set<String> = ["bellisima", "markett", "sbagliatto", "viaggiatto", "swakopmund", "windhoek", "nasa", "ab"]

    func testIssuesCarryThePageAndTheTextTheyBelongTo() async {
        let (book, photo) = book()
        let checker = BookSpelling(checker: FakeChecker(wrong: wrong))
        let issues = await checker.issues(in: book)
        // Swakopmund is a place name, Windhoek is not (no photo there): it is listed.
        XCTAssertEqual(Set(words(issues)), ["bellisima", "markett", "Windhoek", "sbagliatto", "viaggiatto"])
        let byWord = Dictionary(uniqueKeysWithValues: issues.map { (words([$0])[0].lowercased(), $0) })
        XCTAssertEqual(byWord["bellisima"]?.target, .story)
        XCTAssertEqual(byWord["bellisima"]?.pageID, book.pages[0].id)
        XCTAssertEqual(byWord["bellisima"]?.location, .page(1))
        XCTAssertEqual(byWord["markett"]?.target, .textBox(book.pages[0].textBoxes![0].id))
        XCTAssertEqual(byWord["sbagliatto"]?.target, .caption(photo.id))
        XCTAssertEqual(byWord["viaggiatto"]?.target, .cover(front: false))
        XCTAssertEqual(byWord["viaggiatto"]?.location, .cover)
        XCTAssertEqual(Set(issues.map(\.id)).count, issues.count, "ids are unique")
        let again = await checker.issues(in: book)
        XCTAssertEqual(issues.map(\.id), again.map(\.id), "and stable between runs")
    }

    func testIgnoredLearnedPlaceCapitalNumberAndShortWordsAreSkipped() async {
        var (book, _) = book()
        book.pages[0].text = "bellisima NASA ab 42markett bellisima"
        book.ignoredSpellings = ["MARKETT"]
        let fake = FakeChecker(wrong: wrong.union(["42markett"]))
        let spelling = BookSpelling(checker: fake)
        let first = await spelling.issues(in: book)
        XCTAssertEqual(Set(words(first)), ["bellisima", "Windhoek", "sbagliatto", "viaggiatto"],
                       "caps, digits, short words and the place name are skipped; markett is ignored in this book")
        book.ignoredSpellings = ["bellisima", "windhoek", "sbagliatto", "markett"]
        fake.learn("viaggiatto")
        let second = await spelling.issues(in: book)
        XCTAssertEqual(words(second), [])
        // The same word twice in one text is one row.
        book.ignoredSpellings = nil
        let third = await BookSpelling(checker: FakeChecker(wrong: wrong)).issues(in: book)
        XCTAssertEqual(words(third).filter { $0 == "bellisima" }.count, 1)
    }

    func testChangingOneTextRechecksOnlyThatText() async {
        var (book, _) = book()
        let fake = FakeChecker(wrong: wrong)
        let spelling = BookSpelling(checker: fake)
        _ = await spelling.issues(in: book)
        let first = fake.asked.count
        XCTAssertEqual(first, Set(BookSpelling.texts(of: book).map(\.text)).count, "each different text once")
        _ = await spelling.issues(in: book)
        XCTAssertEqual(fake.asked.count, first, "nothing changed, nothing asked")
        book.pages[0].textBoxes?[0].text = "Seen at the markett again"
        _ = await spelling.issues(in: book)
        XCTAssertEqual(fake.asked.count, first + 1)
        XCTAssertEqual(fake.asked.last, "Seen at the markett again")
    }

    func testOnlyCaptionsOfPlacedPhotosAreCheckedAndOnlyOnce() {
        var (book, photo) = book()
        book.pages.append(BookPage(photoIDs: [photo.id]))
        XCTAssertEqual(BookSpelling.texts(of: book).filter { $0.target == .caption(photo.id) }.count, 1)
        book.pages = []
        XCTAssertTrue(BookSpelling.texts(of: book).filter { if case .caption = $0.target { true } else { false } }.isEmpty)
    }

    func testContextAndMessage() {
        let text = "Una giornata molto bellisima nel deserto della Namibia di sera"
        let range = (text as NSString).range(of: "bellisima")
        XCTAssertEqual(BookSpelling.context(of: range, in: text), "Una giornata molto bellisima nel deserto della …")
        let middle = "uno due tre quattro bellisima cinque sei sette otto"
        XCTAssertEqual(BookSpelling.context(of: (middle as NSString).range(of: "bellisima"), in: middle), "… due tre quattro bellisima cinque sei sette …")
        XCTAssertEqual(BookSpelling.context(of: NSRange(location: 0, length: 3), in: "Una casa"), "Una casa")
        let issue = BookPDF.PreflightIssue(location: .page(3), problem: .possibleMisspelling(word: "bellisima", context: "molto bellisima nel"))
        XCTAssertEqual(issue.message(language: "en"), "p. 3 · “bellisima” · molto bellisima nel")
    }

    func testALiteral010ManifestWithoutIgnoredSpellingsDecodesUnchanged() throws {
        let manifest = """
        {"id":"7C1C4F0A-3B5D-4D6E-9F10-2A3B4C5D6E7F","title":"Namibia","schemaVersion":1,
         "format":{"widthMM":210,"heightMM":210},"photos":[],
         "pages":[{"id":"0F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9","layout":"text","photoIDs":[],"text":"Una giornata bellissima"}],
         "writerVersion":1}
        """
        let book = try JSONDecoder().decode(Book.self, from: Data(manifest.utf8))
        XCTAssertNil(book.ignoredSpellings)
        XCTAssertEqual(book.pages[0].text, "Una giornata bellissima")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
        XCTAssertNil(json["ignoredSpellings"], "an unset field is not written")
        var changed = book
        changed.ignoredSpellings = ["markett"]
        XCTAssertEqual(try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(changed)).ignoredSpellings, ["markett"])
    }

    func testHeadingAndStoryShareOneRowPerWord() async {
        var (book, _) = book()
        book.pages[0].heading = "Bellisima"
        book.pages[0].text = "Una giornata bellisima, davvero bellisima"
        let issues = await BookSpelling(checker: FakeChecker(wrong: wrong)).issues(in: book)
        XCTAssertEqual(words(issues).filter { $0.lowercased() == "bellisima" }.count, 1)
        XCTAssertEqual(Set(issues.map(\.id)).count, issues.count)
    }

    func testElisionsHyphensAndCurlyApostrophes() async {
        var (book, _) = book()
        book.photos[0].location = PhotoLocation(name: "Etosha National Park", latitude: -19, longitude: 16)
        book.pages[0].text = "Siamo stati nell’Etosha e dell'Etosha, a Walvis-Etosha, in Sossusvlei"
        let fake = FakeChecker(wrong: ["etosha", "nell’etosha", "dell'etosha", "walvis-etosha", "sossusvlei", "nell", "dell", "walvis"])
        // The fake flags whole tokens as the system does for these forms.
        let spelling = BookSpelling(checker: fake)
        var seen = words(await spelling.issues(in: book))
        XCTAssertEqual(seen.filter { $0.lowercased().contains("etosha") }, [], "a place name covers its elided and hyphenated forms")
        XCTAssertTrue(seen.contains("Sossusvlei"))
        book.ignoredSpellings = ["dell’Sossusvlei"]
        seen = words(await spelling.issues(in: book))
        XCTAssertFalse(seen.contains("Sossusvlei"), "ignoring an elided form covers the bare word")
        XCTAssertEqual(BookSpelling.variants(of: "dell’Etosha"), ["dell'etosha", "etosha"])
        XCTAssertEqual(BookSpelling.variants(of: "Walvis-Bay"), ["walvis-bay"])
        XCTAssertTrue(BookSpelling.isKnown("l’Etosha-Bay", in: ["etosha", "bay"]), "each hyphen part, elided or not")
        XCTAssertTrue(BookSpelling.isKnown("Walvis-Bay", in: ["walvis", "bay"]))
        XCTAssertFalse(BookSpelling.isKnown("Walvis-Bay", in: ["walvis"]))
    }

    func testACancelledRunKeepsTheAnswers() async {
        let (book, _) = book()
        let fake = FakeChecker(wrong: wrong)
        let spelling = BookSpelling(checker: fake)
        _ = await spelling.issues(in: book)
        let asked = fake.asked.count
        let run = Task { await spelling.issues(in: book) }
        run.cancel()
        _ = await run.value
        _ = await spelling.issues(in: book)
        XCTAssertEqual(fake.asked.count, asked, "nothing was dropped by the cancelled run")
    }

    /// Needs the Mac's Italian and English dictionaries, so it is skipped where they are missing.
    func testSystemCheckerFindsAnItalianAndAnEnglishMisspelling() throws {
        let languages = NSSpellChecker.shared.availableLanguages
        try XCTSkipUnless(languages.contains { $0.hasPrefix("it") } && languages.contains { $0.hasPrefix("en") })
        let checker = SystemSpellChecker()
        let italian = "Una giornata bellisima nel deserto, con il cielo azzurro e la sabbia rossa."
        let english = "We had lunch at the markett before the long drive back to the camp."
        func flagged(_ text: String) -> [String] { checker.misspellings(in: text).map { (text as NSString).substring(with: $0) } }
        XCTAssertEqual(flagged(italian), ["bellisima"])
        XCTAssertEqual(flagged(english), ["markett"])
        // Ordinary headings are never flagged whole (the orthography results of `check(_:…)` did that).
        for heading in ["Cena al ristorante", "Deserto del Namib", "Il tramonto sul mare", "Giorno uno"] {
            XCTAssertFalse(flagged(heading).contains(heading), heading)
        }
    }

    /// The language detected for a text is the one used: a German sentence is not checked as English.
    func testSystemCheckerUsesTheDetectedLanguage() throws {
        let languages = NSSpellChecker.shared.availableLanguages
        try XCTSkipUnless(languages.contains { $0.hasPrefix("de") })
        let german = "Wir haben gestern einen langen Spaziergang durch die Wüste gemacht und viel gesehen."
        XCTAssertEqual(SystemSpellChecker.candidateLanguages(for: german), ["de"])
        XCTAssertEqual(SystemSpellChecker().misspellings(in: german).count, 0)
    }

    /// The first pass over a 50-page book: the total, and the longest time the main thread is held at once.
    /// Timing depends on the machine and on a cold start, so it runs only when `PAPERGRAIN_SPELLING_TIMING` is set.
    func testFirstPassOverAFiftyPageBookIsSliced() async throws {
        guard ProcessInfo.processInfo.environment["PAPERGRAIN_SPELLING_TIMING"] != nil else {
            throw XCTSkip("PAPERGRAIN_SPELLING_TIMING is not set")
        }
        let languages = NSSpellChecker.shared.availableLanguages
        try XCTSkipUnless(languages.contains { $0.hasPrefix("it") })
        let story = String(repeating: "Una giornata bellisima nel deserto con il cielo azzurro e la sabbia rossa. ", count: 12)
        let pages = (0..<50).map { story + String($0) }
        let checker = SystemSpellChecker()
        var slices: [Double] = []
        for text in pages {
            let start = ContinuousClock.now
            _ = checker.misspellings(in: text)
            let elapsed = ContinuousClock.now - start
            slices.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        let rest = slices.dropFirst().sorted()
        print(String(format: "SPELL 50 stories (900 chars): %.0f ms in all; first (cold) slice %.1f ms, then median %.1f ms, longest %.1f ms",
                     slices.reduce(0, +), slices[0], rest[rest.count / 2], rest.last ?? 0))
        XCTAssertLessThan(rest.last ?? 0, 40)
    }
}
