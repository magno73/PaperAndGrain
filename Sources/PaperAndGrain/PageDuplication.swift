import Foundation

extension BookPage {
    /// A copy of the page for **Duplicate Page**. The page and each text box get new ids and
    /// `layerOrder` follows the new box ids. Photos keep their ids, because one photo can sit
    /// on several pages; everything else is copied as it is.
    func duplicated() -> BookPage {
        var copy = self
        copy.id = UUID()
        var newIDs: [UUID: UUID] = [:]
        copy.textBoxes = textBoxes?.map { box in
            var box = box
            let id = UUID()
            newIDs[box.id] = id
            box.id = id
            return box
        }
        copy.layerOrder = layerOrder?.compactMap { layer in
            guard case let .textBox(old) = layer else { return layer }
            return newIDs[old].map(PageLayer.textBox)
        }
        return copy
    }
}
