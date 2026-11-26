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
    /// Adds Finder images to the open book; the closure reveals the first imported photo.
    var addPhotoFiles: (@escaping (UUID) -> Void) -> Void = { _ in }
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
    var showsIssues = false
    var gutterGuide = false
    var canBringForward = false
    var canSendBackward = false

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
    var toggleIssues: () -> Void = {}
    var setSpread: (Bool) -> Void = { _ in }
    var zoomIn: () -> Void = {}
    var zoomOut: () -> Void = {}
    var zoomToFit: () -> Void = {}
    var toggleGutter: () -> Void = {}
    var browse: () -> Void = {}
    var moveLayer: (PageLayer.Move) -> Void = { _ in }
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
struct EditorMenus: Commands, Localizing {
    @FocusedValue(\.editorCommands) private var editor
    let language: String

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(editor?.showsNavigator == false ? tr("Show Pages") : tr("Hide Pages")) {
                editor?.toggleNavigator()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(editor == nil)
            Button(editor?.showsInspector == false ? tr("Show Inspector") : tr("Hide Inspector")) {
                editor?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(editor == nil)
            Button(editor?.showsTray == false ? tr("Show Photo Library") : tr("Hide Photo Library")) {
                editor?.toggleTray()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(editor == nil)
            Button(editor?.showsIssues == true ? tr("Hide Issues") : tr("Show Issues")) {
                editor?.toggleIssues()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(editor == nil)
            Divider()
            Button(tr("Single Page")) { editor?.setSpread(false) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(editor == nil)
            Button(tr("Two Pages")) { editor?.setSpread(true) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(editor == nil)
            Divider()
            Button(tr("Zoom In")) { editor?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(editor == nil)
            Button(tr("Zoom Out")) { editor?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(editor == nil)
            Button(tr("Zoom to Fit")) { editor?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(editor == nil)
            Button(editor?.gutterGuide == true ? tr("Hide Gutter Guide")
                                               : tr("Show Gutter Guide")) {
                editor?.toggleGutter()
            }
            .disabled(editor == nil)
            Divider()
            Button(tr("Browse the Book")) { editor?.browse() }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(editor?.hasPage != true)
            Divider()
        }

        CommandMenu(tr("Insert")) {
            Button(tr("Page")) { editor?.insertPage() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button(tr("Text Box")) { editor?.insertTextBox() }
                .disabled(editor?.hasPage != true)
            Button(tr("Page Heading")) { editor?.insertHeading() }
                .disabled(editor?.hasPage != true)
            Button(tr("Title Page")) { editor?.insertTitlePage() }
                .disabled(editor == nil)
        }

        CommandMenu(tr("Page")) {
            Button(tr("Page Layout…")) { editor?.chooseLayout() }
                .disabled(editor?.hasPage != true)
            Divider()
            Button(tr("Previous Page")) { editor?.previousPage() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(editor?.canGoBack != true)
            Button(tr("Next Page")) { editor?.nextPage() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(editor?.canGoForward != true)
            Divider()
            Button(tr("Move Earlier")) { editor?.moveEarlier() }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(editor?.canMoveEarlier != true)
            Button(tr("Move Later")) { editor?.moveLater() }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(editor?.canMoveLater != true)
            Divider()
            Button(tr("Delete Page…")) { editor?.deletePage() }
                .disabled(editor?.hasPage != true)
        }

        CommandMenu(tr("Photo")) {
            Button(tr("Crop")) { editor?.crop() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(editor?.hasPhotoSelection != true)
            Button(tr("Adjust")) { editor?.adjust() }
                .disabled(editor?.hasPhotoSelection != true)
            Button(tr("Auto Enhance")) { editor?.autoEnhance() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(editor?.hasPhotoSelection != true)
            Button(tr("Film Look")) { editor?.film() }
                .disabled(editor == nil)
            Divider()
            Button(tr("Remove from Page")) { editor?.removePhoto() }
                .disabled(editor?.hasPhotoSelection != true)
        }

        CommandMenu(tr("Arrange")) {
            Button(tr("Bring to Front")) { editor?.moveLayer(.front) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(editor?.canBringForward != true)
            Button(tr("Bring Forward")) { editor?.moveLayer(.forward) }
                .keyboardShortcut("f", modifiers: [.command, .shift, .option])
                .disabled(editor?.canBringForward != true)
            Button(tr("Send Backward")) { editor?.moveLayer(.backward) }
                .keyboardShortcut("b", modifiers: [.command, .shift, .option])
                .disabled(editor?.canSendBackward != true)
            Button(tr("Send to Back")) { editor?.moveLayer(.back) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(editor?.canSendBackward != true)
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
