import Foundation
import XCTest
@testable import PaperAndGrain

/// A checker that knows which words are wrong and how often it was asked.
private final class FakeChecker: SpellChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private var learned: Set<String> = []
    let wrong: Set<String>

    init(wrong: Set<String>) { self.wrong = wrong }

    var asked: [String] { lock.withLock { calls } }

    func misspellings(in text: String) -> [NSRange] {
        lock.withLock { calls.append(text) }
        var found: [NSRange] = []
        let string = text as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byWords) { word, range, _, _ in
            if let word, self.wrong.contains(word.lowercased()) { found.append(range) }
        }
        return found
    }

    func hasLearned(_ word: String) -> Bool { lock.withLock { learned.contains(word.lowercased()) } }
    func learn(_ word: String) { lock.withLock { _ = learned.insert(word.lowercased()) } }
}

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

    func testIssuesCarryThePageAndTheTextTheyBelongTo() {
        let (book, photo) = book()
        let checker = BookSpelling(checker: FakeChecker(wrong: wrong))
        let issues = checker.issues(in: book)
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
        XCTAssertEqual(issues.map(\.id), checker.issues(in: book).map(\.id), "and stable between runs")
    }

    func testIgnoredLearnedPlaceCapitalNumberAndShortWordsAreSkipped() {
        var (book, _) = book()
        book.pages[0].text = "bellisima NASA ab 42markett bellisima"
        book.ignoredSpellings = ["MARKETT"]
        let fake = FakeChecker(wrong: wrong.union(["42markett"]))
        let spelling = BookSpelling(checker: fake)
        XCTAssertEqual(Set(words(spelling.issues(in: book))), ["bellisima", "Windhoek", "sbagliatto", "viaggiatto"],
                       "caps, digits, short words and the place name are skipped; markett is ignored in this book")
        book.ignoredSpellings = ["bellisima", "windhoek", "sbagliatto", "markett"]
        fake.learn("viaggiatto")
        XCTAssertEqual(words(spelling.issues(in: book)), [])
        // The same word twice in one text is one row.
        book.ignoredSpellings = nil
        let rows = words(BookSpelling(checker: FakeChecker(wrong: wrong)).issues(in: book)).filter { $0 == "bellisima" }
        XCTAssertEqual(rows.count, 1)
    }

    func testChangingOneTextRechecksOnlyThatText() {
        var (book, _) = book()
        let fake = FakeChecker(wrong: wrong)
        let spelling = BookSpelling(checker: fake)
        _ = spelling.issues(in: book)
        let first = fake.asked.count
        XCTAssertEqual(first, Set(BookSpelling.texts(of: book).map(\.text)).count, "each different text once")
        _ = spelling.issues(in: book)
        XCTAssertEqual(fake.asked.count, first, "nothing changed, nothing asked")
        book.pages[0].textBoxes?[0].text = "Seen at the markett again"
        _ = spelling.issues(in: book)
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

    func testOldBooksWithoutIgnoredSpellingsDecodeAndStayUnchanged() throws {
        let (book, _) = book()
        let data = try JSONEncoder().encode(book)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["ignoredSpellings"], "an unset field is not written")
        let decoded = try JSONDecoder().decode(Book.self, from: data)
        XCTAssertNil(decoded.ignoredSpellings)
        XCTAssertEqual(decoded, book)
        var changed = book
        changed.ignoredSpellings = ["markett"]
        XCTAssertEqual(try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(changed)).ignoredSpellings, ["markett"])
    }

    /// Needs the Mac's Italian and English dictionaries, so it is skipped where they are missing.
    func testSystemCheckerFindsAnItalianAndAnEnglishMisspelling() throws {
        let languages = NSSpellChecker.shared.availableLanguages
        try XCTSkipUnless(languages.contains { $0.hasPrefix("it") } && languages.contains { $0.hasPrefix("en") })
        let checker = SystemSpellChecker()
        let italian = "Una giornata bellisima nel deserto, con il cielo azzurro e la sabbia rossa."
        let english = "We had lunch at the markett before the long drive back to the camp."
        let it = checker.misspellings(in: italian).map { (italian as NSString).substring(with: $0) }
        let en = checker.misspellings(in: english).map { (english as NSString).substring(with: $0) }
        XCTAssertEqual(it, ["bellisima"])
        XCTAssertEqual(en, ["markett"])
        print("SPELL system checker flagged \(it) and \(en)")
    }
}
