import SwiftUI

enum EditorDragItem: Equatable {
    case page(UUID), photo(UUID)
}

struct EditorDragPreview: Equatable {
    let item: EditorDragItem
    let location: CGPoint
}

enum EditorDropTarget: Hashable {
    static let coordinateSpace = "PaperAndGrainEditor"
    case navigatorViewport, canvasViewport, navigatorPage(UUID), canvasPage(UUID), cover(front: Bool)
}

struct EditorDropFrames: PreferenceKey {
    static let defaultValue: [EditorDropTarget: CGRect] = [:]

    static func reduce(value: inout [EditorDropTarget: CGRect], nextValue: () -> [EditorDropTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func editorDropFrame(_ target: EditorDropTarget) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: EditorDropFrames.self,
                                       value: [target: geometry.frame(in: .named(EditorDropTarget.coordinateSpace))])
            }
        }
    }
}
