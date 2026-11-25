import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension EditorView {
    @ViewBuilder var photoAdjustmentsInspector: some View {
        if let selectedPhoto, let photo = indexedPhoto(selectedPhoto) {
            VStack(alignment: .leading, spacing: 10) {
                Text(photo.name).font(.callout.weight(.semibold)).lineLimit(2)
                intro(tr("Le regolazioni seguono la foto in tutto il libro.",
                         "Adjustments follow this photo throughout the book."))
                if let message = adjustmentErrors[photo.id] {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                PhotoAdjustmentsPanel(adjustments: Binding(
                    get: { currentPhotoAdjustmentDraft(for: photo.id) },
                    set: { value in updatePhotoAdjustmentDraft(value, for: photo.id) }
                ), language: language, isEnhancing: enhancingPhotos[photo.id] != nil,
                comparingOriginal: Binding(
                    get: { comparePhotoOriginal == photo.id },
                    set: { comparePhotoOriginal = $0 ? photo.id : nil }
                ), onAutomatic: {
                    autoEnhance(photo)
                }, onReset: {
                    discardPhotoAdjustmentDraft()
                    setPhotoAdjustments(PhotoAdjustments(), for: photo.id)
                }, onEditingChanged: { started in
                    if started {
                        finishPhotoAdjustmentEdit()
                        let values = currentPhotoAdjustmentDraft(for: photo.id)
                        adjustmentEdit = AdjustmentEdit(photoID: photo.id, draft: values, preview: values)
                    } else {
                        finishPhotoAdjustmentEdit()
                    }
                })
                .id(photo.id)
            }
        } else {
            intro(tr("Seleziona una foto nella pagina o nella fototeca.",
                     "Select a photo on the page or in the photo library."))
        }
    }

    func setPhotoAdjustments(_ value: PhotoAdjustments, for id: UUID,
                                     actionName: String? = nil) {
        guard let index = photoIndex(id) else { return }
        enhancingPhotos.removeValue(forKey: id)
        adjustmentErrors.removeValue(forKey: id)
        if comparePhotoOriginal == id { comparePhotoOriginal = nil }
        let normalized = value == PhotoAdjustments() ? nil : value
        let previous = book.photos[index].adjustments
        guard previous != normalized else { return }
        book.photos[index].adjustments = normalized
        if let undoManager {
            let name = actionName ?? tr("Regola foto", "Adjust Photo")
            undoTarget.registerPhotoValue(undoManager, binding: $book, bookID: book.id,
                                         photoID: id, key: \.adjustments, previous: previous, name: name)
        }
    }

    func currentPhotoAdjustmentDraft(for id: UUID) -> PhotoAdjustments {
        if let adjustmentEdit, adjustmentEdit.photoID == id { return adjustmentEdit.draft }
        return indexedPhoto(id)?.adjustments ?? PhotoAdjustments()
    }

    func updatePhotoAdjustmentDraft(_ value: PhotoAdjustments, for id: UUID) {
        guard let adjustmentEdit, adjustmentEdit.photoID == id else {
            setPhotoAdjustments(value, for: id)
            return
        }
        guard adjustmentEdit.draft != value else { return }
        enhancingPhotos.removeValue(forKey: id)
        adjustmentErrors.removeValue(forKey: id)
        if comparePhotoOriginal == id { comparePhotoOriginal = nil }
        self.adjustmentEdit?.draft = value
        guard adjustmentPreviewTask == nil else { return }
        adjustmentPreviewTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(55)) } catch { return }
            adjustmentPreviewTask = nil
            guard let edit = self.adjustmentEdit, edit.photoID == id, edit.preview != edit.draft else { return }
            self.adjustmentEdit?.preview = edit.draft
        }
    }

    func finishPhotoAdjustmentEdit() {
        guard let edit = adjustmentEdit else { return }
        discardPhotoAdjustmentDraft()
        setPhotoAdjustments(edit.draft, for: edit.photoID)
    }

    func discardPhotoAdjustmentDraft() {
        adjustPreviewCleanup()
        adjustmentEdit = nil
    }

    func adjustPreviewCleanup() {
        adjustmentPreviewTask?.cancel()
        adjustmentPreviewTask = nil
    }

    func autoEnhance(_ photo: BookPhoto) {
        finishPhotoAdjustmentEdit()
        guard enhancingPhotos[photo.id] == nil else { return }
        let operation = UUID()
        let bookID = book.id
        let photoID = photo.id
        let url = BookStorage.assetURL(filename: photo.filename, in: directory)
        enhancingPhotos[photoID] = operation
        adjustmentErrors.removeValue(forKey: photoID)
        Task { @MainActor in
            let suggested = await Task.detached(priority: .userInitiated) {
                PhotoAdjustments.automatic(from: url)
            }.value
            guard book.id == bookID, enhancingPhotos[photoID] == operation,
                  let current = indexedPhoto(photoID) else { return }
            enhancingPhotos.removeValue(forKey: photoID)
            guard let suggested else {
                adjustmentErrors[photoID] = tr("Impossibile analizzare questa foto.", "Couldn’t analyze this photo.")
                return
            }
            let adjustments = (current.adjustments ?? PhotoAdjustments()).applyingAutomatic(suggested)
            setPhotoAdjustments(adjustments, for: photoID,
                                actionName: tr("Migliora in automatico", "Auto Enhance"))
        }
    }
}
