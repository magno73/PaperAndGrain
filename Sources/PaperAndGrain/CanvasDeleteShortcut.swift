import AppKit
import SwiftUI

/// Routes an unmodified deletion key to the canvas in its own key window.
struct CanvasDeleteShortcut: NSViewRepresentable {
    let onDelete: () -> Bool

    func makeNSView(context: Context) -> Anchor {
        let anchor = Anchor(frame: .zero)
        anchor.onDelete = onDelete
        return anchor
    }

    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.onDelete = onDelete
    }

    static func dismantleNSView(_ anchor: Anchor, coordinator: ()) {
        anchor.stopMonitoring()
    }

    nonisolated static func isDeleteKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        // Fn-Delete can report the function flag together with the forward delete key code.
        let backspace: UInt16 = 51
        let forwardDelete: UInt16 = 117
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return (keyCode == backspace || keyCode == forwardDelete) && !isRepeat && modifiers.isDisjoint(with: shortcutModifiers)
    }

    final class Anchor: NSView {
        var onDelete: () -> Bool = { false }
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                stopMonitoring()
                return
            }
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    return self.handle(event)
                }
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, window.isKeyWindow, window.attachedSheet == nil,
                  event.window == nil || event.window === window,
                  CanvasDeleteShortcut.isDeleteKey(event.keyCode, modifiers: event.modifierFlags, isRepeat: event.isARepeat),
                  !(window.firstResponder is NSText), !(window.firstResponder is NSTextField)
            else { return event }
            return onDelete() ? nil : event
        }
    }
}
