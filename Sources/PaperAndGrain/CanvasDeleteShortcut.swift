import AppKit
import SwiftUI

enum EditorKeyboardTarget: Equatable {
    case none, canvas, navigatorPage(UUID), navigatorCover

    func deletionTarget(selectedPageID: UUID?) -> Self {
        if case let .navigatorPage(id) = self, id != selectedPageID { return .none }
        return self
    }
}

/// Routes editor commands and observes completed clicks without intercepting pointer events.
struct CanvasDeleteShortcut: NSViewRepresentable {
    let onDelete: () -> Bool
    let onDeselect: () -> Bool
    let onNudge: (CGSize) -> Bool
    /// A completed click and the modifier keys held for it (⇧ or ⌘ add to the selection).
    let onClick: (CGPoint, NSEvent.ModifierFlags) -> Void
    let onPointerDown: (CGPoint) -> Void
    let onKeyboardTraversal: () -> Void
    var onContextMenu: (CGPoint) -> [EditorMenuEntry]? = { _ in nil }
    /// Returns true when a scroll at this point should turn pages instead of scrolling content.
    var canTurnPages: (CGPoint) -> Bool = { _ in false }
    var onTurnPage: (Int) -> Void = { _ in }
    /// ⌘A outside text: returns true when it selected objects on the canvas.
    var onSelectAll: () -> Bool = { false }
    /// Whether a press here may start a selection rectangle (blank paper of a page).
    var canBeginMarquee: (CGPoint) -> Bool = { _ in false }
    /// The selection rectangle from its origin to the pointer; `ended` on release.
    var onMarquee: (_ origin: CGPoint, _ point: CGPoint, _ ended: Bool) -> Void = { _, _, _ in }

    func makeNSView(context: Context) -> Anchor {
        let anchor = Anchor(frame: .zero)
        updateNSView(anchor, context: context)
        return anchor
    }

    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.onDelete = onDelete
        anchor.onDeselect = onDeselect
        anchor.onNudge = onNudge
        anchor.onClick = onClick
        anchor.onPointerDown = onPointerDown
        anchor.onKeyboardTraversal = onKeyboardTraversal
        anchor.onContextMenu = onContextMenu
        anchor.canTurnPages = canTurnPages
        anchor.onTurnPage = onTurnPage
        anchor.onSelectAll = onSelectAll
        anchor.canBeginMarquee = canBeginMarquee
        anchor.onMarquee = onMarquee
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

    nonisolated static func isDeselectKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        guard !isRepeat else { return false }
        let shortcut = modifiers.intersection([.command, .control, .option, .shift])
        return (keyCode == 53 && shortcut.isEmpty) || (keyCode == 0 && shortcut == [.command, .shift])
    }

    /// ⌘A by the character, not the key position: on an AZERTY keyboard the A key position types Q.
    nonisolated static func isSelectAllKey(_ characters: String?, modifiers: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        !isRepeat && characters?.lowercased() == "a" && modifiers.intersection([.command, .control, .option, .shift]) == .command
    }

    /// ⇧ or ⌘ held with a click adds the object to the selection or removes it.
    nonisolated static func extendsSelection(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.isDisjoint(with: [.shift, .command])
    }

    nonisolated static func nudgeOffset(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> CGSize? {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let step: CGFloat = modifiers.contains(.shift) ? 10 : 1
        switch keyCode {
        case 123: return CGSize(width: -step, height: 0)
        case 124: return CGSize(width: step, height: 0)
        case 125: return CGSize(width: 0, height: step)
        case 126: return CGSize(width: 0, height: -step)
        default: return nil
        }
    }

    nonisolated static func isWithinClickDistance(from origin: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return dx * dx + dy * dy < 9
    }

    final class Anchor: NSView {
        var onDelete: () -> Bool = { false }
        var onDeselect: () -> Bool = { false }
        var onNudge: (CGSize) -> Bool = { _ in false }
        var onClick: (CGPoint, NSEvent.ModifierFlags) -> Void = { _, _ in }
        var onSelectAll: () -> Bool = { false }
        var canBeginMarquee: (CGPoint) -> Bool = { _ in false }
        var onMarquee: (CGPoint, CGPoint, Bool) -> Void = { _, _, _ in }
        private var marqueeOrigin: CGPoint?
        private var marqueeActive = false
        var onPointerDown: (CGPoint) -> Void = { _ in }
        var onKeyboardTraversal: () -> Void = {}
        var onContextMenu: (CGPoint) -> [EditorMenuEntry]? = { _ in nil }
        var canTurnPages: (CGPoint) -> Bool = { _ in false }
        var onTurnPage: (Int) -> Void = { _ in }
        private var monitor: Any?
        private var pressOrigin: CGPoint?
        private var pageScroll = PageScrollGesture()

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                stopMonitoring()
                return
            }
            if monitor == nil {
                let mask: NSEvent.EventTypeMask = [
                    .keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel
                ]
                monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    guard let self else { return event }
                    return self.handle(event)
                }
            }
        }

        func stopMonitoring() {
            pressOrigin = nil
            marqueeOrigin = nil
            marqueeActive = false
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
            if event.type == .scrollWheel {
                return turnPages(event, in: window) ? nil : event
            }
            if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
               event.window === window, let contentView = window.contentView {
                pressOrigin = nil
                onKeyboardTraversal()
                let point = convert(event.locationInWindow, from: nil)
                if bounds.contains(point), let entries = onContextMenu(point), !entries.isEmpty {
                    NSMenu.popUpContextMenu(EditorMenuEntry.menu(entries), with: event, for: contentView)
                    return nil
                }
                return event
            }
            if event.type != .keyDown {
                trackClick(event, in: window)
                return event
            }
            guard window.isKeyWindow, event.window == nil || event.window === window else { return event }
            if event.keyCode == 48 { onKeyboardTraversal() } // Tab can move focus to a different control.
            guard !(window.firstResponder is NSText), !(window.firstResponder is NSTextField) else { return event }
            if CanvasDeleteShortcut.isDeleteKey(event.keyCode, modifiers: event.modifierFlags, isRepeat: event.isARepeat) {
                return onDelete() ? nil : event
            }
            if CanvasDeleteShortcut.isDeselectKey(event.keyCode, modifiers: event.modifierFlags, isRepeat: event.isARepeat) {
                return onDeselect() ? nil : event
            }
            if CanvasDeleteShortcut.isSelectAllKey(event.charactersIgnoringModifiers, modifiers: event.modifierFlags,
                                                   isRepeat: event.isARepeat) {
                return onSelectAll() ? nil : event
            }
            if let offset = CanvasDeleteShortcut.nudgeOffset(event.keyCode, modifiers: event.modifierFlags) {
                return onNudge(offset) ? nil : event
            }
            return event
        }

        private func turnPages(_ event: NSEvent, in window: NSWindow) -> Bool {
            guard event.window === window, window.isKeyWindow || window.isMainWindow else { return false }
            let point = convert(event.locationInWindow, from: nil)
            let allowed = bounds.contains(point) && canTurnPages(point)
            switch pageScroll.handle(event, allowed: allowed, now: event.timestamp) {
            case .ignore: return false
            case .consume: return true
            case let .turn(direction):
                onTurnPage(direction)
                return true
            }
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
                onPointerDown(point)
                marqueeOrigin = nil
                marqueeActive = false
                if bounds.contains(point),
                   CanvasDeleteShortcut.isPrimaryMousePress(clickCount: event.clickCount, modifiers: event.modifierFlags) {
                    pressOrigin = location
                    if canBeginMarquee(point) { marqueeOrigin = point }
                } else {
                    pressOrigin = nil
                }
            case .rightMouseDown, .otherMouseDown:
                pressOrigin = nil
                marqueeOrigin = nil
                marqueeActive = false
                onKeyboardTraversal()
            case .leftMouseDragged:
                if let origin = pressOrigin, !CanvasDeleteShortcut.isWithinClickDistance(from: origin, to: location) {
                    pressOrigin = nil
                }
                if let origin = marqueeOrigin {
                    let point = convert(location, from: nil)
                    if marqueeActive || !CanvasDeleteShortcut.isWithinClickDistance(from: origin, to: point) {
                        marqueeActive = true
                        onMarquee(origin, point, false)
                    }
                }
            case .leftMouseUp:
                if let marquee = marqueeOrigin, marqueeActive {
                    onMarquee(marquee, convert(location, from: nil), true)
                }
                marqueeOrigin = nil
                marqueeActive = false
                let origin = pressOrigin
                pressOrigin = nil
                guard let origin, CanvasDeleteShortcut.isWithinClickDistance(from: origin, to: location),
                      CanvasDeleteShortcut.isPrimaryMousePress(clickCount: event.clickCount, modifiers: event.modifierFlags)
                else { return }
                let point = convert(location, from: nil)
                guard bounds.contains(point) else { return }
                let modifiers = event.modifierFlags
                // Let AppKit finish dispatching mouse-up before selection changes replace SwiftUI controls.
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, self.window === window, window.isKeyWindow,
                          window.attachedSheet == nil else { return }
                    self.onClick(point, modifiers)
                }
            default:
                break
            }
        }
    }
}


/// Turns one page per scroll gesture: a trackpad swipe or a wheel notch, never a burst of momentum.
struct PageScrollGesture {
    enum Outcome: Equatable { case ignore, consume, turn(Int) }

    static let threshold: CGFloat = 28
    static let wheelInterval: TimeInterval = 0.28

    private var accumulated: CGFloat = 0
    private var turned = false
    private var owning = false
    private var lastWheelTurn: TimeInterval = -.infinity

    /// Positive means forward: scrolling down or to the right.
    static func forwardDelta(dx: CGFloat, dy: CGFloat) -> CGFloat {
        abs(dx) > abs(dy) ? -dx : -dy
    }

    mutating func handle(_ event: NSEvent, allowed: Bool, now: TimeInterval) -> Outcome {
        handle(phase: event.phase, momentum: event.momentumPhase, precise: event.hasPreciseScrollingDeltas,
               dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, allowed: allowed, now: now)
    }

    mutating func handle(phase: NSEvent.Phase, momentum: NSEvent.Phase, precise: Bool,
                         dx: CGFloat, dy: CGFloat, allowed: Bool, now: TimeInterval) -> Outcome {
        if !momentum.isEmpty { return owning ? .consume : .ignore }
        let delta = Self.forwardDelta(dx: dx, dy: dy)
        if phase.isEmpty {
            // A classic mouse wheel has no gesture phases: one notch, one page.
            owning = false
            guard allowed, delta != 0 else { return .ignore }
            guard now - lastWheelTurn >= Self.wheelInterval || !precise && now - lastWheelTurn >= 0.12 else { return .consume }
            lastWheelTurn = now
            return .turn(delta > 0 ? 1 : -1)
        }
        if phase.contains(.began) || phase.contains(.mayBegin) {
            accumulated = 0
            turned = false
            owning = allowed
        }
        guard owning else { return .ignore }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            accumulated = 0
            return .consume
        }
        accumulated += delta
        guard !turned, abs(accumulated) >= Self.threshold else { return .consume }
        turned = true
        return .turn(accumulated > 0 ? 1 : -1)
    }
}
