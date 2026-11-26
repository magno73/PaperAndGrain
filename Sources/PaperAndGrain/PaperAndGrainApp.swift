import AppKit
import SwiftUI

@main
enum PaperAndGrainEntry {
    @MainActor static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.first == "cli" {
            Task { exit(await BookCLI.run(Array(arguments.dropFirst()))) }
            dispatchMain()
        }
        PaperAndGrainApp.main()
    }
}

struct PaperAndGrainApp: App, Localizing {
    @StateObject private var workspace = Workspace()
    @AppStorage("interfaceLanguage") private var preferredLanguage = "system"
    @State private var showAlbums = false
    @State private var showBookSettings = false
    @State private var showBookTemplates = false
    @State private var showPDFExport = false
    @State private var pendingPDFExport: PendingPDFExport?
    @State private var hasRestored = false

    private struct PendingPDFExport {
        let bookID: UUID
        let directory: URL?
        let request: PDFExportRequest
    }

    private var saveProjectTitle: String {
        workspace.needsSaveLocation ? tr("Save Project…") : tr("Save Project")
    }

    var language: String { L10n.resolve(preferredLanguage) }

    private var editorActions: EditorAppActions {
        EditorAppActions(closeBook: { workspace.closeBook() },
                         showTemplates: { showBookTemplates = true },
                         showBookSettings: { showBookSettings = true },
                         save: workspace.saveProject,
                         saveTitle: saveProjectTitle,
                         saveAs: workspace.saveProjectAs,
                         exportPrint: { workspace.exportPrint(language: language) },
                         addPhotoFiles: { reveal in workspace.addPhotoFiles(language: language, onImported: reveal) },
                         isReadOnly: workspace.isReadOnly,
                         relinkPhotos: { files, done in workspace.relinkPhotos(files, language: language, completion: done) },
                         copyAgainFromPhotos: { ids, done in
                             workspace.copyAgainFromPhotos(ids, language: language, completion: done)
                         })
    }

    var body: some Scene {
        Window("Paper & Grain", id: EditorFilePanels.bookWindowID) {
            Group {
                if let directory = workspace.directory {
                    EditorView(book: $workspace.book, directory: directory, language: language,
                               analysisStatus: analysisStatus, isAnalyzing: workspace.analysisProgress != nil,
                               onAnalyze: { workspace.analyze(language: language) },
                               onDropPhotos: { providers, reveal in
                                   workspace.addDroppedPhotos(providers, language: language, onImported: reveal)
                               },
                               onDropPhotoPromises: { promises, reveal in
                                   workspace.addDroppedPhotoPromises(promises, language: language, onImported: reveal)
                               },
                               onExport: { showPDFExport = true },
                               actions: editorActions)
                        // A Save As copy and its original share the book id: key on the session instead.
                        .id(workspace.editorSession)
                } else {
                    WelcomeView(language: language, recents: workspace.libraryBooks,
                                onAlbums: { showAlbums = true },
                                onFiles: { workspace.importFiles(language: language) },
                                onOpen: workspace.openProject,
                                onOpenRecent: { workspace.openProject(at: $0.url) },
                                onForget: workspace.forgetRecentBook,
                                onDeleteDraft: workspace.deleteDraft,
                                onDemo: { workspace.loadDemo(language: language) })
                        .onAppear { workspace.refreshDrafts() }
                }
            }
            .frame(minWidth: 1020, minHeight: 680)
            .environment(\.locale, Locale(identifier: language))
            .sheet(isPresented: $showAlbums) {
                AlbumPicker(language: language, close: { showAlbums = false }) { photos, title, format in
                    showAlbums = false
                    workspace.start(photos, title: title, format: format, language: language)
                }
            }
            .modifier(BookSettingsSheets(workspace: workspace, language: language,
                                         showSettings: $showBookSettings, showTemplates: $showBookTemplates))
            .onChange(of: workspace.newBookNeedsTemplate) { _, needed in
                // A new book starts by choosing its look; Cancel keeps the base style.
                guard needed else { return }
                workspace.newBookNeedsTemplate = false
                showBookTemplates = true
            }
            .sheet(isPresented: $showPDFExport, onDismiss: runPDFExport) {
                let book = workspace.book
                let directory = workspace.directory
                PDFExportChooser(book: book, directory: directory, language: language, cancel: { showPDFExport = false }) { request in
                    pendingPDFExport = PendingPDFExport(bookID: book.id, directory: directory, request: request)
                    showPDFExport = false
                }
            }
            .overlay {
                if workspace.importing {
                    progressCard(label: tr("Importing photos"), value: workspace.importProgress,
                                 cancel: workspace.cancelImport)
                } else if workspace.savingCopy {
                    progressCard(label: tr("Saving a copy of the book"), value: "", cancel: nil)
                } else if workspace.exporting {
                    progressCard(label: tr("Exporting PDF"),
                                 value: workspace.exportProgress.formatted(.percent.precision(.fractionLength(0))),
                                 cancel: workspace.cancelExport)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let problem = workspace.problem { errorBanner(problem) }
            }
            .onOpenURL { workspace.openProject(at: $0) }
            .onAppear {
                if !hasRestored {
                    hasRestored = true
                    workspace.reopenLastBook()
                }
            }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button(tr("New Book from Photos…")) { showAlbums = true }
                    .keyboardShortcut("n")
                Button(tr("New Book from Files…")) { workspace.importFiles(language: language) }
                Button(tr("Open…"), action: workspace.openProject)
                    .keyboardShortcut("o")
                Menu(tr("Open Recent")) {
                    ForEach(workspace.recentBooks) { recent in
                        Button(recent.title.isEmpty ? recent.url.deletingPathExtension().lastPathComponent : recent.title) {
                            workspace.openProject(at: recent.url)
                        }
                    }
                }
                .disabled(workspace.recentBooks.isEmpty)
                Divider()
                Button(tr("Back to Library")) { workspace.closeBook() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(workspace.directory == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button(saveProjectTitle, action: workspace.saveProject)
                    .keyboardShortcut("s")
                    .disabled(workspace.directory == nil)
                Button(tr("Save As…"), action: workspace.saveProjectAs)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!workspace.canSaveAs)
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button(tr("Book Templates…")) { showBookTemplates = true }
                    .disabled(workspace.directory == nil)
                Button(tr("Book & Print…")) { showBookSettings = true }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(workspace.directory == nil)
                Divider()
                Button(tr("Export PDF…")) { showPDFExport = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(workspace.directory == nil || workspace.book.pages.isEmpty || workspace.exporting)
                Button(tr("Export for Print…")) { workspace.exportPrint(language: language) }
                    .disabled(workspace.directory == nil || workspace.book.pages.isEmpty || workspace.exporting)
            }
            EditorMenus(language: language)
            AboutHelpCommands(language: language)
        }

        Window(tr("Paper & Grain Help"), id: HelpView.windowID) {
            HelpView(language: language)
        }
        .defaultSize(width: 640, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            AppSettingsView(language: language, preferredLanguage: $preferredLanguage)
        }
    }

    private func runPDFExport() {
        guard let pendingPDFExport else { return }
        self.pendingPDFExport = nil
        guard pendingPDFExport.bookID == workspace.book.id, pendingPDFExport.directory == workspace.directory else { return }
        workspace.exportPDF(pendingPDFExport.request, language: language)
    }

    private var analysisStatus: String {
        if let (done, total) = workspace.analysisProgress {
            return tr("Photo analysis") + " · \(done) / \(total)"
        }
        let reviewed = workspace.book.photos.filter { ($0.analysis?.revision ?? 0) >= PhotoAnalysis.currentRevision }.count
        return tr("Photos analysed") + " · \(reviewed) / \(workspace.book.photos.count)"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                workspace.problem = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tr("Dismiss Message"))
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .floatingPanel(cornerRadius: 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func progressCard(label: String, value: String, cancel: (() -> Void)?) -> some View {
        ZStack {
            Color.black.opacity(0.14).ignoresSafeArea()
            VStack(spacing: 15) {
                ProgressView().controlSize(.small)
                Text(label).font(.headline)
                if !value.isEmpty { Text(value).monospacedDigit().foregroundStyle(.secondary) }
                if let cancel { Button(tr("Cancel"), action: cancel) }
            }
            .frame(width: 225)
            .padding(26)
            .floatingPanel(cornerRadius: 22)
        }
    }
}

private struct BookSettingsSheets: ViewModifier, Localizing {
    @Environment(\.undoManager) private var undoManager
    let workspace: Workspace
    let language: String
    @Binding var showSettings: Bool
    @Binding var showTemplates: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showTemplates) {
                if let directory = workspace.directory {
                    BookTemplateChooser(book: workspace.book, directory: directory, language: language,
                                        onCancel: { showTemplates = false }) { template, showPageNumbers in
                        workspace.applyBookTemplate(template, showPageNumbers: showPageNumbers, undoManager: undoManager,
                                                    actionName: tr("Book Template"))
                        showTemplates = false
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                BookSettingsView(book: workspace.book, language: language, close: { showSettings = false }) {
                    title, format, printSettings, cover, typography in
                    workspace.applyBookPrintSettings(title: title, format: format, printSettings: printSettings,
                                                     cover: cover, typography: typography, undoManager: undoManager,
                                                     actionName: tr("Book & Print"))
                    showSettings = false
                }
            }
    }
}

/// Paper & Grain › Settings (⌘,). The interface language lives here instead of the toolbar.
private struct AppSettingsView: View, Localizing {
    let language: String
    @Binding var preferredLanguage: String

    var body: some View {
        Form {
            Picker(tr("App Language"), selection: $preferredLanguage) {
                Text(tr("System Default")).tag("system")
                Text("Italiano").tag("it")
                Text("English").tag("en")
            }
            Text(tr("You can also choose it in System Settings › General › Language & Region › Applications."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, Locale(identifier: language))
    }
}

private struct WelcomeView: View, Localizing {
    let language: String
    let recents: [Workspace.RecentBook]
    let onAlbums: () -> Void
    let onFiles: () -> Void
    let onOpen: () -> Void
    let onOpenRecent: (Workspace.RecentBook) -> Void
    let onForget: (Workspace.RecentBook) -> Void
    let onDeleteDraft: (Workspace.RecentBook) -> Void
    let onDemo: () -> Void
    @State private var draftToDelete: Workspace.RecentBook?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Text("Paper\n& Grain")
                    .font(.system(size: 72, weight: .regular, design: .serif))
                    .tracking(-3.5)
                    .lineSpacing(-6)
                    .foregroundStyle(Theme.welcomeInk)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Paper & Grain")
                Text(tr("Your travels, page by page."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    welcomeButton(tr("New Book from a Photos Album"),
                                  symbol: "photo.on.rectangle", prominent: true, action: onAlbums)
                    welcomeButton(tr("New Book from Finder Files"),
                                  symbol: "folder", action: onFiles)
                    welcomeButton(tr("Open the Sample Book"),
                                  symbol: "book", action: onDemo)
                }
                .frame(maxWidth: 330)
                Spacer()
            }
            .padding(.horizontal, 48)
            .frame(width: 420, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Theme.welcome.ignoresSafeArea())

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(tr("Your Books"))
                        .font(.title2.weight(.bold))
                    Spacer()
                    Button(tr("Open Other…"), action: onOpen)
                }
                if recents.isEmpty {
                    ContentUnavailableView {
                        Label(tr("No Books Yet"), systemImage: "books.vertical")
                    } description: {
                        Text(tr("Choose a Photos album to lay out your first book, or open the sample."))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24, alignment: .top)],
                                  alignment: .leading, spacing: 28) {
                            ForEach(recents) { recent in
                                RecentBookCard(recent: recent, language: language)
                                    .onTapGesture { onOpenRecent(recent) }
                                    .contextMenu {
                                        Button(tr("Open")) { onOpenRecent(recent) }
                                        Button(tr("Show in Finder")) {
                                            NSWorkspace.shared.activateFileViewerSelecting([recent.url])
                                        }
                                        .disabled(recent.isDraft)
                                        Divider()
                                        if recent.isDraft {
                                            Button(tr("Delete Draft…")) { draftToDelete = recent }
                                        } else {
                                            Button(tr("Remove from Recents")) { onForget(recent) }
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { onOpenRecent(recent) }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)
        }
        .alert(tr("Delete This Draft?"),
               isPresented: Binding(get: { draftToDelete != nil }, set: { if !$0 { draftToDelete = nil } }),
               presenting: draftToDelete) { draft in
            Button(tr("Move to Trash"), role: .destructive) { onDeleteDraft(draft) }
            Button(tr("Cancel"), role: .cancel) {}
        } message: { draft in
            let title = draft.title.isEmpty ? tr("Untitled") : draft.title
            Text(tr("“%@” was never saved to a file. The draft will be moved to the Trash.", title))
        }
    }

    private func welcomeButton(_ title: String, symbol: String, prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(prominent ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .background(prominent ? Theme.accent : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RecentBookCard: View, Localizing {
    let recent: Workspace.RecentBook
    let language: String
    @State private var cover: CGImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The square is laid out first; the cover only fills it, so any aspect ratio stays inside.
            Rectangle().fill(Theme.welcomeInk.opacity(0.85))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let cover {
                        Image(decorative: cover, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .clipped()
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(recent.title)
                        .font(.system(size: 17, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(12)
                }
                .clipped()
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                              bottomTrailingRadius: 7, topTrailingRadius: 7, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle().fill(.black.opacity(0.14)).frame(width: 5)
            }
            .shadow(color: .black.opacity(hovering ? 0.28 : 0.18), radius: hovering ? 16 : 10, y: hovering ? 8 : 5)
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.snappy(duration: 0.18), value: hovering)
            VStack(alignment: .leading, spacing: 2) {
                Text(recent.title.isEmpty ? tr("Untitled") : recent.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: recent.coverURL) {
            guard let url = recent.coverURL else { return }
            cover = await Task.detached(priority: .utility) { LocalImages.load(url, maxPixelSize: 420) }.value
        }
    }

    private var details: String {
        let date = recent.opened.formatted(.relative(presentation: .named).locale(Locale(identifier: language)))
        let pages = tr("%lld pages", recent.pageCount)
        return (recent.isDraft ? tr("Draft") + " · " : "") + pages + " · " + date
    }
}
