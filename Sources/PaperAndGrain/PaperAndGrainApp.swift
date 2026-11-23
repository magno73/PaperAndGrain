import AppKit
import SwiftUI

@main
struct PaperAndGrainApp: App {
    @StateObject private var workspace = Workspace()
    @AppStorage("interfaceLanguage") private var preferredLanguage = "system"
    @State private var showAlbums = false
    @State private var hasRestored = false

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
                               onAnalyze: { workspace.analyze(language: language) }, onExport: workspace.exportPDF)
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
                        Button(s("Salva progetto…", "Save Project…"), action: workspace.saveProject)
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
            .overlay {
                if workspace.importing {
                    progressCard(label: s("Importo le immagini", "Importing photos"), value: workspace.importProgress,
                                 cancel: workspace.cancelImport)
                } else if workspace.exporting {
                    progressCard(label: s("Esporto il PDF", "Exporting PDF"), value: "", cancel: nil)
                }
            }
            .alert(s("Paper & Grain", "Paper & Grain"), isPresented: Binding(
                get: { workspace.problem != nil },
                set: { if !$0 { workspace.problem = nil } }
            )) {
                Button("OK") { workspace.problem = nil }
            } message: { Text(workspace.problem ?? "") }
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
                Button(s("Salva progetto…", "Save Project…"), action: workspace.saveProject)
                    .keyboardShortcut("s")
                    .disabled(workspace.directory == nil)
            }
        }
    }

    private var analysisStatus: String {
        if let (done, total) = workspace.analysisProgress {
            return s("Analisi foto", "Photo analysis") + " · \(done) / \(total)"
        }
        let reviewed = workspace.book.photos.filter { $0.analysis != nil }.count
        return s("Foto analizzate", "Photos analysed") + " · \(reviewed) / \(workspace.book.photos.count)"
    }

    private func s(_ it: String, _ en: String) -> String { language == "it" ? it : en }

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
