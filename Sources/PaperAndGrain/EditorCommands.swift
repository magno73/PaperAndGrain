import AppKit
import SwiftUI

/// App-level actions the editor window exposes in its toolbar and title menu.
struct EditorAppActions {
    var closeBook: () -> Void = {}
    var showTemplates: () -> Void = {}
    var showBookSettings: () -> Void = {}
    var save: () -> Void = {}
    var saveTitle = ""
    var saveAs: () -> Void = {}
    var exportPrint: () -> Void = {}
    var importFiles: () -> Void = {}
}

/// Commands of the focused editor, published to the menu bar with `focusedSceneValue`.
struct EditorCommandSet {
    var hasPage = false
    var hasPhotoSelection = false
    var canMoveEarlier = false
    var canMoveLater = false
    var canGoBack = false
    var canGoForward = false
    var showsNavigator = true
    var showsInspector = true
    var showsTray = true
    var showsSpread = true
    var gutterGuide = false

    var insertPage: () -> Void = {}
    var insertTextBox: () -> Void = {}
    var insertHeading: () -> Void = {}
    var insertTitlePage: () -> Void = {}
    var chooseLayout: () -> Void = {}
    var previousPage: () -> Void = {}
    var nextPage: () -> Void = {}
    var moveEarlier: () -> Void = {}
    var moveLater: () -> Void = {}
    var deletePage: () -> Void = {}
    var crop: () -> Void = {}
    var adjust: () -> Void = {}
    var autoEnhance: () -> Void = {}
    var film: () -> Void = {}
    var removePhoto: () -> Void = {}
    var toggleNavigator: () -> Void = {}
    var toggleInspector: () -> Void = {}
    var toggleTray: () -> Void = {}
    var setSpread: (Bool) -> Void = { _ in }
    var zoomIn: () -> Void = {}
    var zoomOut: () -> Void = {}
    var zoomToFit: () -> Void = {}
    var toggleGutter: () -> Void = {}
    var browse: () -> Void = {}
}

private struct EditorCommandsKey: FocusedValueKey {
    typealias Value = EditorCommandSet
}

extension FocusedValues {
    var editorCommands: EditorCommandSet? {
        get { self[EditorCommandsKey.self] }
        set { self[EditorCommandsKey.self] = newValue }
    }
}

/// Insert, Page and Photo menus plus the editor's View items. Every toolbar and canvas
/// action is reachable here, as the Human Interface Guidelines ask.
struct EditorMenus: Commands {
    @FocusedValue(\.editorCommands) private var editor
    let language: String

    private func s(_ it: String, _ en: String) -> String { language == "it" ? it : en }

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(editor?.showsNavigator == false ? s("Mostra pagine", "Show Pages") : s("Nascondi pagine", "Hide Pages")) {
                editor?.toggleNavigator()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(editor == nil)
            Button(editor?.showsInspector == false ? s("Mostra ispettore", "Show Inspector") : s("Nascondi ispettore", "Hide Inspector")) {
                editor?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(editor == nil)
            Button(editor?.showsTray == false ? s("Mostra fototeca", "Show Photo Library") : s("Nascondi fototeca", "Hide Photo Library")) {
                editor?.toggleTray()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(editor == nil)
            Divider()
            Button(s("Pagina singola", "Single Page")) { editor?.setSpread(false) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(editor == nil)
            Button(s("Doppia pagina", "Two Pages")) { editor?.setSpread(true) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(editor == nil)
            Divider()
            Button(s("Zoom avanti", "Zoom In")) { editor?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(editor == nil)
            Button(s("Zoom indietro", "Zoom Out")) { editor?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(editor == nil)
            Button(s("Adatta alla finestra", "Zoom to Fit")) { editor?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(editor == nil)
            Button(editor?.gutterGuide == true ? s("Nascondi guida della piega", "Hide Gutter Guide")
                                               : s("Mostra guida della piega", "Show Gutter Guide")) {
                editor?.toggleGutter()
            }
            .disabled(editor == nil)
            Divider()
            Button(s("Sfoglia il libro", "Browse the Book")) { editor?.browse() }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(editor?.hasPage != true)
            Divider()
        }

        CommandMenu(s("Inserisci", "Insert")) {
            Button(s("Pagina", "Page")) { editor?.insertPage() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button(s("Box di testo", "Text Box")) { editor?.insertTextBox() }
                .disabled(editor?.hasPage != true)
            Button(s("Titolo di pagina", "Page Heading")) { editor?.insertHeading() }
                .disabled(editor?.hasPage != true)
            Button(s("Frontespizio", "Title Page")) { editor?.insertTitlePage() }
                .disabled(editor == nil)
        }

        CommandMenu(s("Pagina", "Page")) {
            Button(s("Modello di pagina…", "Page Layout…")) { editor?.chooseLayout() }
                .disabled(editor?.hasPage != true)
            Divider()
            Button(s("Pagina precedente", "Previous Page")) { editor?.previousPage() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(editor?.canGoBack != true)
            Button(s("Pagina successiva", "Next Page")) { editor?.nextPage() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(editor?.canGoForward != true)
            Divider()
            Button(s("Sposta prima", "Move Earlier")) { editor?.moveEarlier() }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(editor?.canMoveEarlier != true)
            Button(s("Sposta dopo", "Move Later")) { editor?.moveLater() }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(editor?.canMoveLater != true)
            Divider()
            Button(s("Elimina pagina…", "Delete Page…")) { editor?.deletePage() }
                .disabled(editor?.hasPage != true)
        }

        CommandMenu(s("Foto", "Photo")) {
            Button(s("Ritaglia", "Crop")) { editor?.crop() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(editor?.hasPhotoSelection != true)
            Button(s("Regola", "Adjust")) { editor?.adjust() }
                .disabled(editor?.hasPhotoSelection != true)
            Button(s("Migliora in automatico", "Auto Enhance")) { editor?.autoEnhance() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(editor?.hasPhotoSelection != true)
            Button(s("Look pellicola", "Film Look")) { editor?.film() }
                .disabled(editor == nil)
            Divider()
            Button(s("Togli dalla pagina", "Remove from Page")) { editor?.removePhoto() }
                .disabled(editor?.hasPhotoSelection != true)
        }
    }
}

/// A thin, draggable divider that resizes the pane on its leading side.
struct PaneResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let label: String
    @State private var start: Double?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let origin = start ?? width
                        if start == nil { start = width }
                        width = min(range.upperBound, max(range.lowerBound, origin + value.translation.width))
                    }
                    .onEnded { _ in start = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(Int(width))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = min(range.upperBound, width + 20)
                case .decrement: width = max(range.lowerBound, width - 20)
                @unknown default: break
                }
            }
    }
}
