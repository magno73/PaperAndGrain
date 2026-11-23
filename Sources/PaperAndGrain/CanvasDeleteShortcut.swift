import AppKit
import SwiftUI

/// Observes clicks and routes deletion keys within the editor window.
struct CanvasDeleteShortcut: NSViewRepresentable {
    let onDelete: () -> Bool
    let onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> Anchor {
        let anchor = Anchor(frame: .zero)
        updateNSView(anchor, context: context)
        return anchor
    }

    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.onDelete = onDelete
        anchor.onClick = onClick
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

    nonisolated static func isPrimaryMousePress(clickCount: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        clickCount == 1 && !modifiers.contains(.control)
    }

    nonisolated static func isWithinClickDistance(from origin: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return dx * dx + dy * dy < 9
    }

    final class Anchor: NSView {
        var onDelete: () -> Bool = { false }
        var onClick: (CGPoint) -> Void = { _ in }
        private var monitor: Any?
        private var pressOrigin: CGPoint?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                stopMonitoring()
                return
            }
            if monitor == nil {
                let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
                monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    guard let self else { return event }
                    return self.handle(event)
                }
            }
        }

        func stopMonitoring() {
            pressOrigin = nil
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, window.attachedSheet == nil else {
                pressOrigin = nil
                return event
            }
            if event.type != .keyDown {
                trackClick(event, in: window)
                return event
            }
            guard window.isKeyWindow, event.window == nil || event.window === window,
                  CanvasDeleteShortcut.isDeleteKey(event.keyCode, modifiers: event.modifierFlags, isRepeat: event.isARepeat),
                  !(window.firstResponder is NSText), !(window.firstResponder is NSTextField)
            else { return event }
            return onDelete() ? nil : event
        }

        private func trackClick(_ event: NSEvent, in window: NSWindow) {
            guard event.window === window else {
                pressOrigin = nil
                return
            }

            let location = event.locationInWindow
            switch event.type {
            case .leftMouseDown:
                let point = convert(location, from: nil)
                if bounds.contains(point),
                   CanvasDeleteShortcut.isPrimaryMousePress(clickCount: event.clickCount, modifiers: event.modifierFlags) {
                    pressOrigin = location
                } else {
                    pressOrigin = nil
                }
            case .leftMouseDragged:
                if let origin = pressOrigin, !CanvasDeleteShortcut.isWithinClickDistance(from: origin, to: location) {
                    pressOrigin = nil
                }
            case .leftMouseUp:
                let origin = pressOrigin
                pressOrigin = nil
                guard let origin, CanvasDeleteShortcut.isWithinClickDistance(from: origin, to: location),
                      CanvasDeleteShortcut.isPrimaryMousePress(clickCount: event.clickCount, modifiers: event.modifierFlags)
                else { return }
                let point = convert(location, from: nil)
                if bounds.contains(point) { onClick(point) }
            default:
                break
            }
        }
    }
}
