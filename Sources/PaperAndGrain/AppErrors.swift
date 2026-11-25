import Foundation

/// Errors the app shows to the author, in the interface language (Italian or English).
/// Work package 5 moves these strings into the String Catalog.
enum AppError: LocalizedError, Equatable {
    /// The open package was renamed, moved, deleted or its volume was ejected, and it could not be found again.
    case bookMoved(title: String)
    /// The manifest was written by a newer Paper & Grain; the book opens read-only.
    case newerFormat(title: String)
    /// The package is on a locked or read-only volume, or the author cannot write to it.
    case readOnlyLocation(title: String)
    /// `manifest.json` is not valid JSON or does not describe a book.
    case damagedManifest(package: String)
    /// An image could not be read or copied. The name is the file's when it is known.
    case imageUnavailable(name: String?)
    /// Some images of an import could not be read; the others were added.
    case someImagesUnavailable(imported: Int, unavailable: [String?])

    var errorDescription: String? {
        switch self {
        case let .bookMoved(title):
            return Self.s("\(Self.it(title, or: "Il libro")) è stato spostato, rinominato o non è più disponibile. Usa Salva con nome per conservare le modifiche in un’altra posizione.",
                          "\(Self.en(title, or: "The book")) was moved, renamed or is no longer available. Use Save As to keep your changes in another place.")
        case let .newerFormat(title):
            return Self.s("\(Self.it(title, or: "Questo libro")) è stato salvato con una versione più recente di Paper & Grain. È aperto in sola lettura: le modifiche non verranno salvate. Aggiorna l’app per modificarlo.",
                          "\(Self.en(title, or: "This book")) was saved by a newer version of Paper & Grain. It is open read-only and changes will not be saved. Update the app to edit it.")
        case let .readOnlyLocation(title):
            return Self.s("\(Self.it(title, or: "Questo libro")) si trova in una posizione in sola lettura. Le modifiche non verranno salvate finché non usi Salva con nome per copiarlo altrove.",
                          "\(Self.en(title, or: "This book")) is in a read-only location. Changes will not be saved until you use Save As to copy it somewhere else.")
        case let .damagedManifest(package):
            return Self.s("Impossibile aprire \(Self.it(package, or: "il libro")): il file manifest.json è danneggiato o non descrive un libro.",
                          "\(Self.en(package, or: "The book")) can’t be opened: its manifest.json file is damaged or does not describe a book.")
        case let .imageUnavailable(name):
            guard let name, !name.isEmpty else {
                return Self.s("L’immagine non è disponibile o non è in un formato leggibile.",
                              "The image is unavailable or not in a readable format.")
            }
            return Self.s("«\(name)» non è disponibile o non è in un formato leggibile.",
                          "“\(name)” is unavailable or not in a readable format.")
        case let .someImagesUnavailable(imported, unavailable):
            let names = unavailable.compactMap { $0 }.filter { !$0.isEmpty }
            let listed = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
            let failed = unavailable.count
            let italian = (imported == 1 ? "Importata 1 foto. " : "Importate \(imported) foto. ")
                + (failed == 1 ? "1 immagine non era disponibile" : "\(failed) immagini non erano disponibili")
                + (names.isEmpty ? "." : ": \(listed).")
            let english = (imported == 1 ? "Imported 1 photo. " : "Imported \(imported) photos. ")
                + (failed == 1 ? "1 image was unavailable" : "\(failed) images were unavailable")
                + (names.isEmpty ? "." : ": \(listed).")
            return Self.s(italian, english)
        }
    }

    /// Maps a failed write to the open package to a message the author can act on.
    static func saving(_ error: Error, title: String) -> Error {
        if error is AppError { return error }
        let nsError = error as NSError
        let readOnlyCocoa: Set<Int> = [CocoaError.fileWriteVolumeReadOnly.rawValue, CocoaError.fileWriteNoPermission.rawValue]
        if nsError.domain == NSCocoaErrorDomain, readOnlyCocoa.contains(nsError.code) {
            return AppError.readOnlyLocation(title: title)
        }
        let posix = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
            ?? (nsError.domain == NSPOSIXErrorDomain ? nsError.code : nil)
        if let posix, [Int(EROFS), Int(EACCES), Int(EPERM)].contains(posix) {
            return AppError.readOnlyLocation(title: title)
        }
        return error
    }

    /// Maps a failed open to a message that names the package.
    static func opening(_ error: Error, at url: URL) -> Error {
        error is DecodingError ? AppError.damagedManifest(package: url.deletingPathExtension().lastPathComponent) : error
    }

    /// The interface language chosen in Settings, as `PaperAndGrainApp` resolves it.
    static var interfaceLanguage: String {
        let preferred = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system"
        guard preferred == "system" else { return preferred }
        return Locale.preferredLanguages.first?.hasPrefix("it") == true ? "it" : "en"
    }

    static func s(_ italian: String, _ english: String) -> String {
        interfaceLanguage == "it" ? italian : english
    }

    private static func it(_ name: String, or fallback: String) -> String { name.isEmpty ? fallback : "«\(name)»" }
    private static func en(_ name: String, or fallback: String) -> String { name.isEmpty ? fallback : "“\(name)”" }
}
