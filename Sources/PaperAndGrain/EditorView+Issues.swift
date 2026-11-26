import SwiftUI

extension EditorView {
    /// The print profile the live check runs: the book's print-service product when it chose one in
    /// **Book & Print**, otherwise Generic Print.
    var issuesProfile: BookPDF.Profile { PrintPlan(book: book).map { .service($0) } ?? .print }

    /// Runs the check again after the book has been quiet for a moment.
    func recheckIssues(immediately: Bool = false) {
        issues.bookChanged(book, directory: directory, profile: issuesProfile, immediately: immediately)
    }

    var issuesButtonLabel: some View {
        let report = issues.report
        let blockers = report?.blockers.count ?? 0
        let warnings = report?.warnings.count ?? 0
        return Group {
            if report == nil {
                Label(tr("Issues"), systemImage: "circle.dotted")
                    .labelStyle(.iconOnly)
            } else if blockers + warnings == 0 {
                Label(tr("Issues"), systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
            } else {
                Label {
                    Text(blockers + warnings, format: .number)
                        .foregroundStyle(blockers > 0 ? Color.red : Color.primary)
                } icon: {
                    // A different shape when something blocks the export, so color is not the only cue.
                    Image(systemName: blockers > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityLabel(issuesAccessibilityLabel)
    }

    /// The counts in words, for VoiceOver.
    var issuesAccessibilityLabel: String {
        guard let report = issues.report else { return tr("Issues") + ": " + tr("Checking the book…") }
        if report.isClean { return tr("Issues") + ": " + tr("No issues") }
        var parts = [String]()
        if !report.blockers.isEmpty { parts.append(tr("%lld problems", report.blockers.count)) }
        if !report.warnings.isEmpty { parts.append(tr("%lld warnings", report.warnings.count)) }
        return tr("Issues") + ": " + parts.joined(separator: ", ")
    }

    var issuesPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Issues"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let report = issues.report {
                IssueScroll(maxHeight: 380) {
                    IssueList(report: report, language: language,
                              emptyText: tr("The book is ready for print."),
                              open: revealIssue, fix: issueFix, listFixes: issueListFixes)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(tr("Checking the book…")).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
    }

    /// The spelling of the book's texts, when Settings allows it. It runs on the main actor, one text at a
    /// time, after the preflight.
    nonisolated static let liveSpelling: IssueMonitor.Extra = { book in
        guard UserDefaults.standard.object(forKey: "checkSpellingInIssues") as? Bool ?? true else { return [] }
        return await BookSpelling.shared.issues(in: book)
    }

    /// **Ignore in This Book** (one undo step) with **Learn Spelling** next to it.
    func spellingFix(for word: String) -> IssueFix {
        let learn = IssueFix(title: tr("Learn Spelling"),
                             help: tr("Add the word to the Mac’s dictionary, for every app"),
                             systemImage: "character.book.closed") {
            BookSpelling.shared.learn(word)
            recheckIssues(immediately: true)
        }
        return IssueFix(title: tr("Ignore in This Book"),
                        help: tr("Stop flagging this word in this book"),
                        systemImage: "eye.slash", perform: { ignoreSpelling(word) }, alternates: [learn])
    }

    func ignoreSpelling(_ word: String) {
        let previous = book.ignoredSpellings
        var words = previous ?? []
        guard !words.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        words.append(word)
        book.ignoredSpellings = words
        if let undoManager {
            undoTarget.registerIgnoredSpellings(undoManager, binding: $book, bookID: book.id,
                                                previous: previous, name: tr("Ignore Spelling"))
        }
    }

    /// The remedy a row offers. Every kind is listed, so a new one cannot be forgotten: it stops
    /// compiling here until it says whether it has a fix.
    func issueFix(for issue: BookPDF.PreflightIssue) -> IssueFix? {
        switch issue.problem {
        case .missingFile:
            relinkFix(for: issue)
        case let .possibleMisspelling(word, _):
            spellingFix(for: word)
        case .invalidDimensions, .missingPhoto, .unreadableLUT, .lowResolution, .textOverflows,
             .textOutsideSafeMargin, .photoNearEdge, .blankPages, .sizeNotOffered, .pageCount, .missingMeasure,
             .captionDoesNotFit, .colorProfileUnusable, .colorModeNotAccepted, .outOfGamut, .mapWithoutPlaces, .mapDataMissing:
            nil
        }
    }

    /// Goes to the page or cover face an issue is about and selects its object.
    func revealIssue(_ issue: BookPDF.PreflightIssue) {
        guard let destination = issue.destination(in: book) else { return }
        editorInput.target = .canvas
        switch destination {
        case let .cover(front):
            selectCover(front ? .front : .back)
        case let .page(id):
            guard let leaf = book.pages.first(where: { $0.id == id }) else { return }
            select(leaf)
            guard let target = issue.target else { return }
            switch target {
            case let .photo(photoID):
                if book.photo(photoID) != nil, leaf.photoIDs.contains(photoID) { selectCanvasPhoto(photoID, in: leaf) }
            case let .textBox(boxID):
                if leaf.textBoxes?.contains(where: { $0.id == boxID }) == true { selectTextBox(boxID, in: leaf) }
            case .story:
                if let role = storyRole(of: leaf) { selectEditorial(.page(leaf.id, role), on: leaf) }
            case let .caption(photoID):
                // A caption belongs to its photo: select the photo, whose tab edits the caption.
                if book.photo(photoID) != nil, leaf.photoIDs.contains(photoID) { selectCanvasPhoto(photoID, in: leaf) }
            case .cover:
                break
            }
        }
        if case let .possibleMisspelling(word, _) = issue.problem { openForEditing(issue, word: word) }
    }

    /// A spelling row opens its text for typing, so the word can be corrected where it is.
    private func openForEditing(_ issue: BookPDF.PreflightIssue, word: String) {
        switch (issue.destination(in: book), issue.target) {
        case let (.cover(front)?, _):
            editingEditorial = .cover(front ? .front : .back)
        case let (.page(id)?, target?):
            guard let leaf = book.pages.first(where: { $0.id == id }) else { return }
            switch target {
            case .story:
                let wanted: PageComposition.TextRole = leaf.heading?.localizedCaseInsensitiveContains(word) == true ? .title : .body
                let roles = PageComposition(page: leaf, book: book).storyDrawingBlocks(page: leaf, book: book).map(\.role)
                guard let role = roles.contains(wanted) ? wanted : storyRole(of: leaf) else { return }
                editingEditorial = .page(leaf.id, role)
            case let .textBox(boxID):
                if leaf.textBoxes?.contains(where: { $0.id == boxID }) == true { beginInlineBoxEditing(boxID, in: leaf) }
            case let .caption(photoID):
                beginCaptionEditing(photoID, in: leaf)
            case .photo, .cover:
                break
            }
        default:
            break
        }
    }

    /// The story block that overflows, or the first one when none does.
    private func storyRole(of leaf: BookPage) -> PageComposition.TextRole? {
        let blocks = PageComposition(page: leaf, book: book).storyDrawingBlocks(page: leaf, book: book)
        let overflowing = blocks.first { $0.text.length > 0 && !EditorialTypesetter.fits($0.text, in: $0.frame) }
        return (overflowing ?? blocks.first)?.role
    }
}
