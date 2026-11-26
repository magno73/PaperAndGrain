import AppKit
import Foundation
import NaturalLanguage
import SwiftUI

/// What the whole-book spelling check needs from a spell checker. The app uses `SystemSpellChecker`;
/// tests inject a fake, so they do not depend on the dictionaries installed on the Mac. `NSSpellChecker` has no
/// documented thread safety and AppKit uses the shared one on the main thread while the author types, so the
/// check runs on the main actor, one text at a time.
@MainActor
protocol SpellChecking {
    /// Possible misspellings in `text` as UTF-16 ranges. The checker detects the language of the text.
    func misspellings(in text: String) -> [NSRange]
    /// True when the author taught the system dictionary this word.
    func hasLearned(_ word: String) -> Bool
    func learn(_ word: String)
}

/// `NSSpellChecker` behind the protocol. The language of each text is detected (Italian and English first; a
/// text clearly in another language the Mac has a dictionary for is checked in that one) and passed to
/// `checkSpelling(of:startingAt:language:…)`, which honours it; the options-based `check(_:…)` detects the
/// language itself and ignores the one asked for, and mixes in orthography results. A text whose language has
/// no dictionary is not checked. A short text is judged in Italian and in English and flagged only where both
/// agree.
@MainActor
final class SystemSpellChecker: SpellChecking {
    private let tag = NSSpellChecker.uniqueSpellDocumentTag()

    func misspellings(in text: String) -> [NSRange] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let checker = NSSpellChecker.shared
        let languages = Self.candidateLanguages(for: text).compactMap { code in
            checker.availableLanguages.first { $0 == code || $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
        }
        let length = (text as NSString).length
        var flagged: Set<NSRange>?
        for language in languages {
            var found = Set<NSRange>()
            var location = 0
            while location < length {
                let range = checker.checkSpelling(of: text, startingAt: location, language: language, wrap: false,
                                                  inSpellDocumentWithTag: tag, wordCount: nil)
                guard range.location != NSNotFound, range.length > 0 else { break }
                found.insert(range)
                location = NSMaxRange(range)
            }
            flagged = flagged.map { $0.intersection(found) } ?? found
        }
        return (flagged ?? []).sorted { $0.location < $1.location }
    }

    /// Italian or English first; the text's own language when it is clearly another one.
    nonisolated static func candidateLanguages(for text: String) -> [String] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard let best = hypotheses.max(by: { $0.value < $1.value }), words >= 3, best.value >= 0.5 else {
            return ["it", "en"]
        }
        return [best.key.rawValue]
    }

    func hasLearned(_ word: String) -> Bool { NSSpellChecker.shared.hasLearnedWord(word) }

    func learn(_ word: String) { NSSpellChecker.shared.learnWord(word) }
}

/// The whole-book spelling check: every book text is checked once, the answers are kept, and a text that did
/// not change since the last run is not checked again. It runs on the main actor, one text at a time, and
/// yields between texts so typing is never held up for more than one text (a story takes a few milliseconds).
@MainActor
final class BookSpelling {
    /// The checker the editor's live list uses.
    static let shared = BookSpelling(checker: SystemSpellChecker())

    private let checker: SpellChecking
    private var answers: [String: [NSRange]] = [:]

    init(checker: SpellChecking) { self.checker = checker }

    /// Teaches the system dictionary a word.
    func learn(_ word: String) { checker.learn(word) }

    /// Words shorter than this are not checked.
    nonisolated static let shortestWord = 3

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
    nonisolated static func texts(of book: Book) -> [Text] {
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
    nonisolated static func placeWords(in book: Book) -> Set<String> {
        var words = Set<String>()
        for name in book.photos.compactMap({ $0.location?.name }) {
            for word in name.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "’" && $0 != "'" }) {
                words.insert(String(word))
            }
        }
        return words
    }

    /// A word to leave alone: too short, a number or containing digits, all capitals.
    nonisolated static func isExempt(_ word: String) -> Bool {
        word.count < shortestWord
            || word.contains(where: \.isNumber)
            || (word == word.uppercased() && word.contains(where: \.isLetter))
    }

    /// Apostrophes written as ’ are read as '.
    nonisolated static func normalized(_ word: String) -> String {
        word.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "ʼ", with: "'").lowercased()
    }

    /// A word and its form after an elided article or preposition (dell'Etosha gives Etosha, l'Etosha too).
    /// Place names and ignored words are matched against both, so ignoring "dell'Etosha" also covers
    /// "Etosha" and "nell'Etosha".
    nonisolated static func variants(of word: String) -> [String] {
        let whole = normalized(word)
        guard let apostrophe = whole.firstIndex(of: "'"), whole.distance(from: whole.startIndex, to: apostrophe) <= 5 else {
            return [whole]
        }
        let rest = String(whole[whole.index(after: apostrophe)...])
        return rest.isEmpty ? [whole] : [whole, rest]
    }

    /// True when the word, or its form after an elision, is in `known` (normalised), or when it is hyphenated and
    /// each of its parts is (Swakopmund-Walvis for two place names).
    nonisolated static func isKnown(_ word: String, in known: Set<String>) -> Bool {
        if variants(of: word).contains(where: known.contains) { return true }
        let pieces = normalized(word).split(separator: "-").map(String.init)
        return pieces.count > 1 && pieces.allSatisfy { piece in variants(of: piece).contains(where: known.contains) }
    }

    /// The possible misspellings in `book` as warnings: one row for each different word of each page and
    /// target (a heading and a story are one target). It yields between texts and stops when cancelled.
    func issues(in book: Book) async -> [BookPDF.PreflightIssue] {
        var known = Set<String>()
        for word in book.ignoredSpellings ?? [] { known.formUnion(Self.variants(of: word)) }
        for word in Self.placeWords(in: book) { known.formUnion(Self.variants(of: word)) }
        var issues: [BookPDF.PreflightIssue] = []
        var used = Set<String>()
        var reported = Set<String>()
        for item in Self.texts(of: book) {
            if Task.isCancelled { return issues }
            used.insert(item.text)
            let ranges = answer(for: item.text)
            let string = item.text as NSString
            for range in ranges where NSMaxRange(range) <= string.length {
                let word = string.substring(with: range)
                let place = (item.pageID?.uuidString ?? "cover") + "|" + item.target.key + "|" + Self.normalized(word)
                guard !Self.isExempt(word), !Self.isKnown(word, in: known), !checker.hasLearned(word),
                      reported.insert(place).inserted else { continue }
                issues.append(BookPDF.PreflightIssue(
                    location: item.location,
                    problem: .possibleMisspelling(word: word, context: Self.context(of: range, in: item.text)),
                    pageID: item.pageID, target: item.target, excerpt: item.excerpt))
            }
            await Task.yield()
        }
        // Keep only the answers still in use, so the memory does not grow with every edit. A cancelled run
        // has not visited every text, so it keeps them all.
        if !Task.isCancelled { answers = answers.filter { used.contains($0.key) } }
        return issues
    }

    /// The checker's answer for a text, from memory when the text has not changed.
    private func answer(for text: String) -> [NSRange] {
        if let known = answers[text] { return known }
        let found = checker.misspellings(in: text)
        answers[text] = found
        return found
    }

    /// A few words before and after the word, so the row says where it is.
    nonisolated static func context(of range: NSRange, in text: String, words: Int = 3) -> String {
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
        background(SpellCheckingEnabler())
    }
}

/// Switches on continuous spell checking in the control that sits next to it. SwiftUI's `TextEditor` is an
/// `NSTextView` and `TextField` an `NSTextField` underneath, and whether they underline depends on a
/// system-wide switch the author may never have flipped, so the app sets it where book text is typed.
/// Language detection stays automatic, so Italian and English are both checked. The probe touches only the
/// controls that overlap it (the one it is the background of), switches a text view on when it appears and a
/// text field's shared field editor on when the field becomes first responder, and puts the field editor back
/// when editing ends, so no other field is affected. Autocorrection stays off: place names must not change.
private struct SpellCheckingEnabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = SpellProbe()
        view.isHidden = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

@MainActor
private final class SpellProbe: NSView {
    private var observation: NSKeyValueObservation?
    private var restore: (editor: NSTextView, was: Bool)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guard let window else {
            restoreFieldEditor()
            return
        }
        // After layout, when the control is in place.
        DispatchQueue.main.async { [weak self] in self?.enableTextView() }
        observation = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.responderChanged() }
        }
    }

    /// The siblings that sit under this probe: the control it is the background of.
    private var neighbours: [NSView] {
        superview?.subviews.filter { $0 !== self && $0.frame.intersects(frame) } ?? []
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        if let text = view as? NSTextView, !text.isFieldEditor { return [text] }
        return view.subviews.flatMap { textViews(in: $0) }
    }

    private func enableTextView() {
        for text in neighbours.flatMap({ textViews(in: $0) }) {
            text.isContinuousSpellCheckingEnabled = true
            text.isAutomaticSpellingCorrectionEnabled = false
        }
    }

    private func responderChanged() {
        restoreFieldEditor()
        guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor,
              let field = editor.delegate as? NSTextField, neighbours.contains(field) else { return }
        restore = (editor, editor.isContinuousSpellCheckingEnabled)
        editor.isContinuousSpellCheckingEnabled = true
        editor.isAutomaticSpellingCorrectionEnabled = false
    }

    private func restoreFieldEditor() {
        guard let (editor, was) = restore else { return }
        editor.isContinuousSpellCheckingEnabled = was
        restore = nil
    }
}
