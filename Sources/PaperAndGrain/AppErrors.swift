import Foundation

/// Errors the app shows to the author, in the interface language.
enum AppError: LocalizedError, Equatable {
    /// The open package was renamed, moved, deleted or its volume was ejected, and it could not be found again.
    case bookMoved(title: String)

    var errorDescription: String? {
        switch self {
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
