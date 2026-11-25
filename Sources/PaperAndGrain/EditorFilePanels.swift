import AppKit

/// The app edits one book window. Keep its file dialogs attached to that window and
/// return from the button action immediately, including when there is no window yet.
@MainActor
enum EditorFilePanels {
    private static var presenting = false

    /// The book window. The Help and Settings windows can be key too (⌘S while reading Help),
    /// but a document sheet never belongs there.
    static let bookWindowID = "book"

    private static var parentWindow: NSWindow? {
        // The app has a single book window; prefer it even when Help or Settings is key.
        if let book = NSApp.windows.first(where: {
            $0.sheetParent == nil && $0.identifier?.rawValue.hasPrefix(bookWindowID) == true && isBookWindow($0)
        }) {
            return book
        }
        for candidate in [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 }) {
            let window = candidate.sheetParent ?? candidate
            if isBookWindow(window) { return window }
        }
        // The key window may temporarily be nil as an alert sheet finishes.
        return NSApp.windows.first { window in
            window.isVisible && window.sheetParent == nil && isBookWindow(window)
        }
    }

    static func isBookWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.canBecomeMain else { return false }
        let identifier = window.identifier?.rawValue ?? ""
        return !identifier.hasPrefix(HelpView.windowID) && !identifier.localizedCaseInsensitiveContains("settings")
    }

    static func present(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        let owner = parentWindow
        guard !presenting, owner?.attachedSheet == nil, owner != nil || NSApp.isActive else {
            completion(.cancel)
            return
        }
        presenting = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            panel.orderOut(nil)
            presenting = false
            completion(response)
        }
        if let owner {
            panel.beginSheetModal(for: owner, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    static func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard !presenting, let owner = parentWindow, owner.attachedSheet == nil else {
            completion(.cancel)
            return
        }
        presenting = true
        alert.beginSheetModal(for: owner) { response in
            // AppKit finishes dismissing its alert after this completion returns.
            // Start a subsequent file sheet on the next pass through the event loop.
            DispatchQueue.main.async {
                presenting = false
                completion(response)
            }
        }
    }
}
