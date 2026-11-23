import AppKit
import SwiftUI

/// Receives promised image files from macOS apps without changing the SwiftUI grid's hosting view.
struct PhotoPromiseDropTarget: NSViewRepresentable {
    let onTargeted: (Bool) -> Void
    let onDrop: ([NSFilePromiseReceiver]) -> Bool

    func makeNSView(context: Context) -> TargetView {
        let view = TargetView()
        view.registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        return view
    }

    func updateNSView(_ view: TargetView, context: Context) {
        view.onTargeted = onTargeted
        view.onDrop = onDrop
    }

    final class TargetView: NSView {
        var onTargeted: (Bool) -> Void = { _ in }
        var onDrop: ([NSFilePromiseReceiver]) -> Bool = { _ in false }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard sender.draggingSourceOperationMask.contains(.copy),
                  sender.draggingPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
            else { return [] }
            onTargeted(true)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onTargeted(false)
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            onTargeted(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { onTargeted(false) }
            let items = sender.draggingPasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            guard let promises = items as? [NSFilePromiseReceiver], !promises.isEmpty else { return false }
            return onDrop(promises)
        }
    }
}
