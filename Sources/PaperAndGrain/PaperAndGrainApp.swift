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

struct PaperAndGrainApp: App {
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
        workspace.needsSaveLocation ? s("Salva progetto…", "Save Project…") : s("Salva progetto", "Save Project")
    }

    private var language: String {
        preferredLanguage == "system"
            ? (Locale.preferredLanguages.first?.hasPrefix("it") == true ? "it" : "en")
            : preferredLanguage
    }

    var body: some Scene {
        Window("Paper & Grain", id: "book") {
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
                               onExport: { showPDFExport = true })
                        .id(workspace.book.id)
                } else {
                    WelcomeView(language: language, onAlbums: { showAlbums = true },
                                onFiles: { workspace.importFiles(language: language) },
                                onOpen: workspace.openProject, onDemo: { workspace.loadDemo(language: language) })
                }
            }
            .frame(minWidth: 980, minHeight: 680)
            .environment(\.locale, Locale(identifier: language))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if workspace.directory != nil {
                        Button(action: workspace.closeBook) {
                            Label(s("Libreria", "Library"), systemImage: "books.vertical")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if workspace.directory != nil {
                        Menu {
                            Button(s("Modelli del libro…", "Book Templates…")) { showBookTemplates = true }
                            Button(s("Libro e stampa…", "Book & Print…")) { showBookSettings = true }
                            Button(saveProjectTitle, action: workspace.saveProject)
                            Button(s("Salva con nome…", "Save As…"), action: workspace.saveProjectAs)
                            Divider()
                            Button(s("Esporta per la stampa…", "Export for Print…")) {
                                workspace.exportPrint(language: language)
                            }
                            .disabled(workspace.book.pages.isEmpty || workspace.exporting)
                        } label: {
                            Label(s("Libro e stampa", "Book & Print"), systemImage: "book.closed")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(s("Lingua dell’interfaccia", "App Language"), selection: $preferredLanguage) {
                            Text(s("Come il sistema", "System Default")).tag("system")
                            Text("Italiano").tag("it")
                            Text("English").tag("en")
                        }
                    } label: { Image(systemName: "globe") }
                    .accessibilityLabel(s("Lingua dell’interfaccia", "App Language"))
                }
            }
            .sheet(isPresented: $showAlbums) {
                AlbumPicker(language: language, close: { showAlbums = false }) { photos, title, format in
                    showAlbums = false
                    workspace.start(photos, title: title, format: format, language: language)
                }
            }
            .modifier(BookSettingsSheets(workspace: workspace, language: language,
                                         showSettings: $showBookSettings, showTemplates: $showBookTemplates))
            .sheet(isPresented: $showPDFExport, onDismiss: runPDFExport) {
                let book = workspace.book
                let directory = workspace.directory
                PDFExportChooser(book: book, language: language, cancel: { showPDFExport = false }) { request in
                    pendingPDFExport = PendingPDFExport(bookID: book.id, directory: directory, request: request)
                    showPDFExport = false
                }
            }
            .overlay {
                if workspace.importing {
                    progressCard(label: s("Importo le immagini", "Importing photos"), value: workspace.importProgress,
                                 cancel: workspace.cancelImport)
                } else if workspace.exporting {
                    progressCard(label: s("Esporto il PDF", "Exporting PDF"), value: "", cancel: workspace.cancelExport)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let problem = workspace.problem { errorBanner(problem) }
            }
            .onChange(of: workspace.book) { _, _ in workspace.scheduleSave() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                workspace.flushSave()
            }
            .onOpenURL { workspace.openProject(at: $0) }
            .onAppear {
                if !hasRestored {
                    hasRestored = true
                    workspace.reopenLastBook()
                }
            }
        }
        .defaultSize(width: 1330, height: 840)
        .commands {
            CommandGroup(after: .newItem) {
                Button(s("Nuovo da Foto…", "New from Photos…")) { showAlbums = true }
                    .keyboardShortcut("n")
                Button(s("Apri progetto…", "Open Project…"), action: workspace.openProject)
                    .keyboardShortcut("o")
                Button(saveProjectTitle, action: workspace.saveProject)
                    .keyboardShortcut("s")
                    .disabled(workspace.directory == nil)
                Button(s("Salva con nome…", "Save As…"), action: workspace.saveProjectAs)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(workspace.directory == nil)
                Button(s("Esporta PDF…", "Export PDF…")) { showPDFExport = true }
                    .disabled(workspace.book.pages.isEmpty || workspace.exporting)
            }
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
            return s("Analisi foto", "Photo analysis") + " · \(done) / \(total)"
        }
        let reviewed = workspace.book.photos.filter { ($0.analysis?.revision ?? 0) >= PhotoAnalysis.currentRevision }.count
        return s("Foto analizzate", "Photos analysed") + " · \(reviewed) / \(workspace.book.photos.count)"
    }

    private func s(_ it: String, _ en: String) -> String { language == "it" ? it : en }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
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
            .accessibilityLabel(s("Chiudi avviso", "Dismiss Message"))
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func progressCard(label: String, value: String, cancel: (() -> Void)?) -> some View {
        ZStack {
            Color.black.opacity(0.14).ignoresSafeArea()
            VStack(spacing: 15) {
                ProgressView().controlSize(.small)
                Text(label).font(.headline)
                if !value.isEmpty { Text(value).monospacedDigit().foregroundStyle(.secondary) }
                if let cancel { Button(s("Annulla", "Cancel"), action: cancel) }
            }
            .frame(width: 225)
            .padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct BookSettingsSheets: ViewModifier {
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
                                        onCancel: { showTemplates = false }) { template in
                        workspace.applyBookTemplate(template, undoManager: undoManager,
                                                    actionName: language == "it" ? "Modello del libro" : "Book Template")
                        showTemplates = false
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                BookSettingsView(book: workspace.book, language: language, close: { showSettings = false }) {
                    title, format, printSettings, cover, typography in
                    workspace.applyBookPrintSettings(title: title, format: format, printSettings: printSettings,
                                                     cover: cover, typography: typography, undoManager: undoManager,
                                                     actionName: language == "it" ? "Libro e stampa" : "Book & Print")
                    showSettings = false
                }
            }
    }
}

private struct WelcomeView: View {
    let language: String
    let onAlbums: () -> Void
    let onFiles: () -> Void
    let onOpen: () -> Void
    let onDemo: () -> Void

    private func s(_ it: String, _ en: String) -> String { language == "it" ? it : en }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer()
                    Text("Paper\n& Grain")
                        .font(.system(size: 80, weight: .regular, design: .serif))
                        .tracking(-5)
                        .lineSpacing(-4)
                        .foregroundStyle(Color(red: 0.16, green: 0.25, blue: 0.20))
                        .accessibilityAddTraits(.isHeader)
                    Text(s("I tuoi viaggi, pagina dopo pagina.", "Your travels, page by page."))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: onAlbums) { Label(s("Scegli un album da Foto", "Choose an Album from Photos"), systemImage: "photo.on.rectangle") }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(Color(red: 0.19, green: 0.34, blue: 0.27))
                        HStack {
                            Button(s("Importa file…", "Import Files…"), action: onFiles)
                            Button(s("Apri progetto…", "Open Project…"), action: onOpen)
                        }
                        Button(s("Apri il libro dimostrativo", "Open the Sample Book"), action: onDemo)
                            .buttonStyle(.link)
                    }
                    Spacer()
                }
                .padding(.horizontal, 50)
                .frame(width: proxy.size.width * 0.49, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(Color(red: 0.97, green: 0.95, blue: 0.90))
                if let source = Bundle.main.url(forResource: "Demo", withExtension: "png"), let picture = NSImage(contentsOf: source) {
                    Image(nsImage: picture)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width * 0.51, height: proxy.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
