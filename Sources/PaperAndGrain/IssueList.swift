import SwiftUI

/// A one-click remedy for an issue, shown as a button on its row. A later task gives a kind of
/// problem its fix by returning one from `EditorView.issueFix(for:)`.
struct IssueFix {
    let title: String
    let help: String
    var systemImage: String?
    let perform: () -> Void
}

/// The rows of a preflight result: problems, then warnings, each under the page it belongs to.
/// The editor's Issues popover and the export sheet both show this view, so they never disagree.
struct IssueList: View, Localizing {
    let report: BookPDF.Preflight
    let language: String
    var emptyText: String
    /// Called when a row is clicked; nil makes the rows plain text, as in the modal export sheet.
    var open: ((BookPDF.PreflightIssue) -> Void)?
    var fix: (BookPDF.PreflightIssue) -> IssueFix? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if report.isClean {
                Label(emptyText, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .symbolRenderingMode(.multicolor)
            }
            section(.blocker, title: tr("Problems"))
            section(.warning, title: tr("Warnings"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func section(_ severity: BookPDF.IssueSeverity, title: String) -> some View {
        let groups = report.groups(of: severity)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(heading(group.location))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        ForEach(group.issues) { issue in row(issue, severity: severity) }
                    }
                }
            }
        }
    }

    private func heading(_ location: BookPDF.PreflightIssue.Location?) -> String {
        switch location {
        case nil: tr("Whole book")
        case let .page(number)?: tr("Page %lld", number)
        case .cover?: tr("Cover")
        }
    }

    private func row(_ issue: BookPDF.PreflightIssue, severity: BookPDF.IssueSeverity) -> some View {
        let tint: Color = severity == .blocker ? .red : .orange
        let message = issue.message(language: language, includingPlace: false)
        let kind = severity == .blocker ? tr("Problem") : tr("Warning")
        return HStack(spacing: 6) {
            if let open {
                Button { open(issue) } label: { content(issue, message: message, tint: tint) }
                    .buttonStyle(.plain)
                    .help(tr("Go to the page and select it"))
                    .accessibilityLabel(kind + ": " + message)
                    .accessibilityHint(tr("Go to the page and select it"))
            } else {
                content(issue, message: message, tint: tint)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(kind + ": " + message)
            }
            if let fix = fix(issue) {
                Button(fix.title) { fix.perform() }
                    .controlSize(.small)
                    .help(fix.help)
                    .accessibilityHint(fix.help)
            }
        }
    }

    private func content(_ issue: BookPDF.PreflightIssue, message: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: issue.problem.symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// The list inside a limited height: it scrolls only when it does not fit.
struct IssueScroll<Content: View>: View {
    let maxHeight: Double
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxHeight: maxHeight)
    }
}
