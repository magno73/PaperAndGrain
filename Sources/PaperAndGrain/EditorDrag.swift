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
    case navigatorViewport, canvasViewport
    case navigatorPage(UUID), canvasPage(UUID), cover(front: Bool)
}

struct EditorDropFrames: PreferenceKey {
    static let defaultValue: [EditorDropTarget: CGRect] = [:]

    static func reduce(value: inout [EditorDropTarget: CGRect], nextValue: () -> [EditorDropTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct LibraryPhotoFrames: Equatable, PreferenceKey {
    static let defaultValue = Self()

    var viewport: CGRect? = nil
    var tiles: [UUID: CGRect] = [:]

    static func reduce(value: inout Self, nextValue: () -> Self) {
        let next = nextValue()
        value.viewport = next.viewport ?? value.viewport
        value.tiles.merge(next.tiles, uniquingKeysWith: { _, latest in latest })
    }

    func photo(at point: CGPoint) -> UUID? {
        guard viewport?.contains(point) == true else { return nil }
        return tiles.first { $0.value.contains(point) }?.key
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

    func libraryPhotoFrame(_ id: UUID? = nil) -> some View {
        background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(EditorDropTarget.coordinateSpace))
                Color.clear.preference(key: LibraryPhotoFrames.self,
                                       value: id.map { LibraryPhotoFrames(tiles: [$0: frame]) }
                                           ?? LibraryPhotoFrames(viewport: frame))
            }
        }
    }
}
