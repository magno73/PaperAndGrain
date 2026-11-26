import AppKit
import Foundation
import NaturalLanguage
import SwiftUI

/// What the whole-book spelling check needs from a spell checker. The app uses `SystemSpellChecker`;
/// tests inject a fake, so they do not depend on the dictionaries installed on the Mac.
protocol SpellChecking: Sendable {
    /// Possible misspellings in `text` as UTF-16 ranges. The checker detects the language of the text.
    func misspellings(in text: String) -> [NSRange]
    /// True when the author taught the system dictionary this word.
    func hasLearned(_ word: String) -> Bool
    func learn(_ word: String)
}

/// `NSSpellChecker` behind the protocol. Italian and English come first; other languages the Mac has a
/// dictionary for are used when the text is clearly in one of them. A text whose language has no dictionary
/// is not checked. A lock serializes the calls, because the shared checker is not meant for concurrent use.
final class SystemSpellChecker: SpellChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let tag = NSSpellChecker.uniqueSpellDocumentTag()

    func misspellings(in text: String) -> [NSRange] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let checker = NSSpellChecker.shared
        let languages = Self.candidateLanguages(for: text).compactMap { code in
            checker.availableLanguages.first { $0 == code || $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
        }
        // A short text is judged in each candidate language and flagged only where all of them agree.
        var flagged: Set<NSRange>?
        for language in languages {
            let results = checker.check(text, range: NSRange(location: 0, length: (text as NSString).length),
                                        types: NSTextCheckingResult.CheckingType.spelling.rawValue,
                                        options: [.orthography: NSOrthography.defaultOrthography(forLanguage: language)],
                                        inSpellDocumentWithTag: tag, orthography: nil, wordCount: nil)
            let ranges = Set(results.map(\.range))
            flagged = flagged.map { $0.intersection(ranges) } ?? ranges
        }
        return (flagged ?? []).sorted { $0.location < $1.location }
    }

    /// Italian or English first; the text's own language when it is clearly another one.
    static func candidateLanguages(for text: String) -> [String] {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = [.italian: 0.45, .english: 0.45]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard let best = hypotheses.max(by: { $0.value < $1.value }), words >= 3, best.value >= 0.5 else {
            return ["it", "en"]
        }
        return [best.key.rawValue]
    }

    func hasLearned(_ word: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return NSSpellChecker.shared.hasLearnedWord(word)
    }

    func learn(_ word: String) {
        lock.lock()
        defer { lock.unlock() }
        NSSpellChecker.shared.learnWord(word)
    }
}

/// The whole-book spelling check: every book text is checked once, the answers are kept, and a text that did
/// not change since the last run is not checked again. Safe to call from a background task.
final class BookSpelling: @unchecked Sendable {
    /// The checker the editor's live list uses.
    static let shared = BookSpelling(checker: SystemSpellChecker())

    private let checker: SpellChecking
    private let lock = NSLock()
    private var answers: [String: [NSRange]] = [:]

    init(checker: SpellChecking) { self.checker = checker }

    /// Teaches the system dictionary a word.
    func learn(_ word: String) { checker.learn(word) }

    /// Words shorter than this are not checked.
    static let shortestWord = 3

    /// One text of the book and where it is.
    struct Text {
        let text: String
        let location: BookPDF.PreflightIssue.Location
        let pageID: UUID?
        let target: BookPDF.IssueTarget
        let excerpt: String?
    }

    /// Every text the author typed that appears in the book: headings and stories, text boxes, the captions of
    /// photos that sit on a page (once, on the first page that has the photo), the cover title and back text.
    static func texts(of book: Book) -> [Text] {
        var found: [Text] = []
        var captioned = Set<UUID>()
        for (page, number) in zip(book.pages, Book.pageNumbers(of: book.pages)) {
            let place = BookPDF.PreflightIssue.Location.page(number)
            for story in [page.heading, page.text] {
                if let story, !story.isEmpty {
                    found.append(Text(text: story, location: place, pageID: page.id, target: .story, excerpt: nil))
                }
            }
            for box in page.textBoxes ?? [] where !box.text.isEmpty {
                found.append(Text(text: box.text, location: place, pageID: page.id, target: .textBox(box.id),
                                  excerpt: BookPDF.excerpt(of: box.text)))
            }
            for id in page.photoIDs where captioned.insert(id).inserted {
                if let caption = book.photo(id)?.caption, !caption.isEmpty {
                    found.append(Text(text: caption, location: place, pageID: page.id, target: .caption(id),
                                      excerpt: BookPDF.excerpt(of: caption)))
                }
            }
        }
        if let cover = book.cover {
            if !cover.title.isEmpty {
                found.append(Text(text: cover.title, location: .cover, pageID: nil, target: .cover(front: true), excerpt: nil))
            }
            if let back = cover.backText, !back.isEmpty {
                found.append(Text(text: back, location: .cover, pageID: nil, target: .cover(front: false), excerpt: nil))
            }
        }
        return found
    }

    /// Words of the photos' place names: a travel book is full of them.
    static func placeWords(in book: Book) -> Set<String> {
        var words = Set<String>()
        for name in book.photos.compactMap({ $0.location?.name }) {
            for word in name.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "’" && $0 != "'" }) {
                words.insert(String(word))
            }
        }
        return words
    }

    /// A word to leave alone: too short, a number or containing digits, all capitals.
    static func isExempt(_ word: String) -> Bool {
        word.count < shortestWord
            || word.contains(where: \.isNumber)
            || (word == word.uppercased() && word.contains(where: \.isLetter))
    }

    /// The possible misspellings in `book` as warnings: one row for each different word of each text.
    func issues(in book: Book) -> [BookPDF.PreflightIssue] {
        let ignored = Set((book.ignoredSpellings ?? []).map { $0.lowercased() })
        let places = Self.placeWords(in: book)
        var issues: [BookPDF.PreflightIssue] = []
        var used = Set<String>()
        for item in Self.texts(of: book) {
            if Task.isCancelled { break }
            used.insert(item.text)
            let ranges = answer(for: item.text)
            let string = item.text as NSString
            var seen = Set<String>()
            for range in ranges where NSMaxRange(range) <= string.length {
                let word = string.substring(with: range)
                let key = word.lowercased()
                guard !Self.isExempt(word), !ignored.contains(key), !places.contains(key),
                      !checker.hasLearned(word), seen.insert(key).inserted else { continue }
                issues.append(BookPDF.PreflightIssue(
                    location: item.location,
                    problem: .possibleMisspelling(word: word, context: Self.context(of: range, in: item.text)),
                    pageID: item.pageID, target: item.target, excerpt: item.excerpt))
            }
        }
        // Keep only the answers still in use, so the memory does not grow with every edit.
        lock.withLock { answers = answers.filter { used.contains($0.key) } }
        return issues
    }

    /// The checker's answer for a text, from memory when the text has not changed.
    private func answer(for text: String) -> [NSRange] {
        if let known = lock.withLock({ answers[text] }) { return known }
        let found = checker.misspellings(in: text)
        lock.withLock { answers[text] = found }
        return found
    }

    /// A few words before and after the word, so the row says where it is.
    static func context(of range: NSRange, in text: String, words: Int = 3) -> String {
        guard let span = Range(range, in: text) else { return "" }
        let before = text[..<span.lowerBound].split(whereSeparator: \.isWhitespace).suffix(words).joined(separator: " ")
        let after = text[span.upperBound...].split(whereSeparator: \.isWhitespace).prefix(words).joined(separator: " ")
        let middle = String(text[span])
        let whole = [before, middle, after].filter { !$0.isEmpty }.joined(separator: " ")
        let startsHere = text[..<span.lowerBound].split(whereSeparator: \.isWhitespace).count <= words
        let endsHere = text[span.upperBound...].split(whereSeparator: \.isWhitespace).count <= words
        return (startsHere ? "" : "… ") + whole + (endsHere ? "" : " …")
    }
}

// MARK: Spell checking while typing

extension View {
    /// Every place where book text is typed checks spelling as you type, in the language of the text.
    func checksSpelling() -> some View {
        autocorrectionDisabled(false).background(SpellCheckingEnabler())
    }
}

/// Switches on continuous spell checking in the text view or text field that sits next to it. SwiftUI's
/// `TextEditor` and `TextField` are `NSTextView` and `NSTextField` underneath, and whether they underline
/// depends on a system-wide switch the author may never have flipped, so the app sets it where book text is
/// typed. Language detection stays automatic, so Italian and English are both checked.
private struct SpellCheckingEnabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = SpellProbe()
        view.isHidden = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    final class SpellProbe: NSView {
        private nonisolated(unsafe) var observer: NSObjectProtocol?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            DispatchQueue.main.async { [weak self] in self?.enable() }
            guard observer == nil else { return }
            // A text field edits through the window's field editor, created when editing starts.
            observer = NotificationCenter.default.addObserver(
                forName: NSControl.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] note in
                // The notification is delivered on the main queue, so it never leaves the main thread.
                nonisolated(unsafe) let note = note
                MainActor.assumeIsolated {
                    guard let field = note.object as? NSTextField, let root = self?.superview,
                          field.isDescendant(of: root) || field.superview === root.superview else { return }
                    (note.userInfo?["NSFieldEditor"] as? NSTextView)?.isContinuousSpellCheckingEnabled = true
                }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.enable() }
        }

        /// The editor's text view is a sibling or a descendant of a sibling.
        private func enable() {
            guard let root = superview else { return }
            for case let text as NSTextView in Self.descendants(of: root) {
                text.isContinuousSpellCheckingEnabled = true
                text.isAutomaticSpellingCorrectionEnabled = false
            }
        }

        private static func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }

        deinit { observer.map(NotificationCenter.default.removeObserver) }
    }
}
