import AppKit

/// The app edits one book window. Keep its file dialogs attached to that window and
/// return from the button action immediately, including when there is no window yet.
@MainActor
enum EditorFilePanels {
    private static var presenting = false

    private static var parentWindow: NSWindow? {
        for candidate in [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 }) {
            let window = candidate.sheetParent ?? candidate
            if !(window is NSPanel), window.canBecomeMain { return window }
        }
        // The key window may temporarily be nil as an alert sheet finishes.
        return NSApp.windows.first { window in
            window.isVisible && window.canBecomeMain && !(window is NSPanel) && window.sheetParent == nil
        }
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
