import AppKit
import Photos
import SwiftUI

/// Relinking photos whose file is gone from the package: the commands the issue row, the photo menus and
/// the **Photo** tab share. The copying goes through the workspace and the drop import path.
extension EditorView {
    /// Missing photos can only be repaired where the package can be written.
    var canRelink: Bool { !actions.isReadOnly }

    func isFileMissing(_ id: UUID) -> Bool { missingFileIDs.contains(id) }

    /// Looks for the photo files off the main thread and publishes the ids whose file is gone.
    func refreshMissingFiles() {
        let photos = book.photos
        let folder = directory
        missingFileTask?.cancel()
        missingFileTask = Task {
            let missing = await Task.detached(priority: .utility) {
                Set(PhotoRelink.missing(in: photos, directory: folder).map(\.id))
            }.value
            if !Task.isCancelled, missing != missingFileIDs { missingFileIDs = missing }
        }
    }

    /// The commands for one missing photo, for context menus. Empty for a photo whose file is there.
    func relinkEntries(for photoID: UUID) -> [EditorMenuEntry] {
        guard isFileMissing(photoID) else { return [] }
        var entries = [EditorMenuEntry(tr("Relink…"), enabled: canRelink) { relink(photoID) }]
        if book.photos.first(where: { $0.id == photoID })?.sourceID != nil {
            entries.append(EditorMenuEntry(tr("Copy Again from Photos"), enabled: canRelink) { copyAgainFromPhotos(photoID) })
        }
        return entries + [.separator]
    }

    /// The remedy on an issue row for a missing file.
    func relinkFix(for issue: BookPDF.PreflightIssue) -> IssueFix? {
        guard canRelink, case let .photo(id)? = issue.target else { return nil }
        return IssueFix(title: tr("Relink…"), help: tr("Choose the image file for this photo"),
                        systemImage: "link") { relink(id) }
    }

    /// Buttons under the whole list: relinking from a folder pays off from two missing files.
    func issueListFixes(_ report: BookPDF.Preflight) -> [IssueFix] {
        let missing = report.blockers.filter { if case .missingFile = $0.problem { true } else { false } }
        guard canRelink, missing.count >= 2 else { return [] }
        return [IssueFix(title: tr("Relink All from Folder…"),
                         help: tr("Choose a folder; photos are matched to files by their original name"),
                         systemImage: "folder") { relinkAllFromFolder() }]
    }

    /// The Photo tab's row for a missing photo.
    @ViewBuilder func missingPhotoRow(_ photo: BookPhoto) -> some View {
        if isFileMissing(photo.id) {
            VStack(alignment: .leading, spacing: 6) {
                Label(tr("Photo file missing"), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                HStack {
                    Button(tr("Relink…")) { relink(photo.id) }
                        .help(tr("Choose the image file for this photo"))
                    if photo.sourceID != nil {
                        Button(tr("Copy Again from Photos")) { copyAgainFromPhotos(photo.id) }
                            .help(tr("Fetch the original from the Photos library again"))
                    }
                }
                .controlSize(.small)
                .disabled(!canRelink)
            }
        }
    }

    // MARK: One photo

    func relink(_ id: UUID) {
        guard canRelink, let photo = book.photos.first(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = tr("Choose the image file for “%@”", photo.name)
        EditorFilePanels.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            actions.relinkPhotos([id: url]) { report in showRelinkReport(report) }
        }
    }

    func copyAgainFromPhotos(_ id: UUID) {
        guard canRelink else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            presentRelinkAlert(
                title: tr("No access to Photos"),
                message: tr("Paper & Grain does not have access to your Photos library. Allow it in System Settings › Privacy & Security › Photos, then try again, or use Relink… to choose the file."))
            return
        }
        actions.copyAgainFromPhotos([id]) { report in showRelinkReport(report) }
    }

    // MARK: From a folder

    func relinkAllFromFolder() {
        guard canRelink else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = tr("Choose the folder that holds the original photos")
        EditorFilePanels.present(panel) { response in
            guard response == .OK, let folder = panel.url else { return }
            let photos = book.photos
            let package = directory
            Task {
                let found = await Task.detached(priority: .userInitiated) { () -> (matches: [UUID: URL], unmatched: [BookPhoto]) in
                    let missing = PhotoRelink.missing(in: photos, directory: package)
                    return PhotoRelink.match(missing: missing, files: PhotoRelink.imageFiles(in: folder))
                }.value
                confirmRelink(matches: found.matches, unmatched: found.unmatched)
            }
        }
    }

    private func confirmRelink(matches: [UUID: URL], unmatched: [BookPhoto]) {
        let total = matches.count + unmatched.count
        guard !matches.isEmpty else {
            presentRelinkAlert(title: tr("No matching photos"),
                               message: tr("No file in that folder has the name of a missing photo."))
            return
        }
        var message = tr("Missing photos found: %1$lld of %2$lld.", matches.count, total)
        if !unmatched.isEmpty { message += "\n\n" + tr("Not found: %@", nameList(unmatched.map(\.name))) }
        message += "\n\n" + tr("The files are copied into the book. Relinking cannot be undone with ⌘Z.")
        presentRelinkAlert(title: tr("Relink Photos"), message: message, confirm: tr("Relink")) {
            actions.relinkPhotos(matches) { report in showRelinkReport(report) }
        }
    }

    // MARK: Messages

    func showRelinkReport(_ report: PhotoRelink.Report) {
        var lines = [tr("Photos relinked: %lld.", report.relinked)]
        if !report.failed.isEmpty { lines.append(tr("Not relinked: %@", nameList(report.failed))) }
        if !report.proportionsChanged.isEmpty {
            lines.append(tr("The proportions of these photos changed, so their crops may have shifted: %@",
                            nameList(report.proportionsChanged)))
        }
        presentRelinkAlert(title: tr("Relink Photos"), message: lines.joined(separator: "\n\n"))
    }

    private func nameList(_ names: [String]) -> String {
        names.prefix(8).joined(separator: ", ") + (names.count > 8 ? "…" : "")
    }

    private func presentRelinkAlert(title: String, message: String, confirm: String? = nil,
                                    onConfirm: @escaping () -> Void = {}) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm ?? tr("OK"))
        if confirm != nil { alert.addButton(withTitle: tr("Cancel")) }
        EditorFilePanels.present(alert) { response in
            if confirm != nil, response == .alertFirstButtonReturn { onConfirm() }
        }
    }
}
