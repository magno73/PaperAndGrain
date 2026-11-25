import Foundation

/// Errors the app shows to the author, in the interface language; the strings are in the String Catalog.
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
            return Self.tr("%@ was moved, renamed or is no longer available. Use Save As to keep your changes in another place.",
                           Self.quoted(title, or: Self.tr("The book")))
        case let .newerFormat(title):
            return Self.tr("%@ was saved by a newer version of Paper & Grain. It is open read-only and changes will not be saved. Update the app to edit it.",
                           Self.quoted(title, or: Self.tr("This book")))
        case let .readOnlyLocation(title):
            return Self.tr("%@ is in a read-only location. Changes will not be saved until you use Save As to copy it somewhere else.",
                           Self.quoted(title, or: Self.tr("This book")))
        case let .damagedManifest(package):
            return Self.tr("%@ can’t be opened: its manifest.json file is damaged or does not describe a book.",
                           Self.quoted(package, or: L10n.string("error.damaged_book", language: Self.language, default: "The book")))
        case let .imageUnavailable(name):
            guard let name, !name.isEmpty else {
                return Self.tr("The image is unavailable or not in a readable format.")
            }
            return Self.tr("“%@” is unavailable or not in a readable format.", name)
        case let .someImagesUnavailable(imported, unavailable):
            let names = unavailable.compactMap { $0 }.filter { !$0.isEmpty }
            let listed = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
            return Self.tr("Imported %lld photos.", imported) + " "
                + Self.tr("%lld images were unavailable", unavailable.count)
                + (names.isEmpty ? "." : ": \(listed).")
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

    /// Errors read the interface language chosen in Settings (English in the CLI).
    private static var language: String { L10n.interfaceLanguage }

    private static func tr(_ key: String) -> String { L10n.string(key, language: language) }

    private static func tr(_ format: String, _ arguments: any CVarArg...) -> String {
        L10n.format(format, language: language, arguments)
    }

    /// A book or file name in the language's quotation marks, or the fallback when it has none.
    private static func quoted(_ name: String, or fallback: String) -> String {
        name.isEmpty ? fallback : tr("“%@”", name)
    }
}
