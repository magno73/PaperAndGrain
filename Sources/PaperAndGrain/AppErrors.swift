import Foundation

/// Errors the app shows to the author, in the interface language.
enum AppError: LocalizedError, Equatable {
    /// The open package was renamed, moved, deleted or its volume was ejected, and it could not be found again.
    case bookMoved(title: String)
    /// The manifest was written by a newer Paper & Grain; the book opens read-only.
    case newerFormat(title: String)
    /// The package is on a locked or read-only volume, or the author cannot write to it.
    case readOnlyLocation(title: String)

    var errorDescription: String? {
        switch self {
        case let .newerFormat(title):
            return Self.s("\(title.isEmpty ? "Questo libro" : "«\(title)»") è stato salvato con una versione più recente di Paper & Grain. È aperto in sola lettura: le modifiche non verranno salvate. Aggiorna l’app per modificarlo.",
                          "\(title.isEmpty ? "This book" : "“\(title)”") was saved by a newer version of Paper & Grain. It is open read-only and changes will not be saved. Update the app to edit it.")
        case let .readOnlyLocation(title):
            return Self.s("\(title.isEmpty ? "Questo libro" : "«\(title)»") si trova in una posizione in sola lettura. Le modifiche non verranno salvate finché non usi Salva con nome per copiarlo altrove.",
                          "\(title.isEmpty ? "This book" : "“\(title)”") is in a read-only location. Changes will not be saved until you use Save As to copy it somewhere else.")
        case let .bookMoved(title):
            return Self.s("\(title.isEmpty ? "Il libro" : "«\(title)»") è stato spostato, rinominato o non è più disponibile. Usa Salva con nome per conservare le modifiche in un’altra posizione.",
                          "\(title.isEmpty ? "The book" : "“\(title)”") was moved, renamed or is no longer available. Use Save As to keep your changes in another place.")
        }
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
}
