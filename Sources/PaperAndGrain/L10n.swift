import Foundation

/// Interface strings in the language chosen in Settings › Language.
///
/// Every visible string lives in `Resources/Localizable.xcstrings`. English is the source language and
/// the English text is the key (`tr("Page")`). Where one English text needs different Italian
/// translations, the key is explicit and the English text is its default (`tr("Layout", key: "toolbar.layout")`).
/// Interpolated strings are format strings with positional specifiers (`tr("%lld pages", count)`); the
/// catalog's plural variations choose "1 page" or "2 pages" for the language.
///
/// `scripts/build-app.sh` compiles the catalog into `en.lproj` and `it.lproj` inside the app. Lookups
/// read the bundle of the chosen language, not the system locale. Without the compiled catalog
/// (`swift test`, `swift run`) every lookup returns its English key or default.
enum L10n {
    /// The one test for the Italian interface; every other language reads English.
    static func isItalian(_ language: String) -> Bool { language.lowercased().hasPrefix("it") }

    /// `it` or `en`.
    static func code(_ language: String) -> String { isItalian(language) ? "it" : "en" }

    /// The interface language for a Settings preference: `system`, `it` or `en`.
    static func resolve(_ preference: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard preference == "system" else { return code(preference) }
        return code(preferredLanguages.first ?? "en")
    }

    /// The interface language outside a view, as `PaperAndGrainApp` resolves Settings › Language.
    /// The CLI always reads English.
    static var interfaceLanguage: String {
        if state.withLock({ $0.englishOnly }) { return "en" }
        return resolve(UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system")
    }

    /// The CLI calls this before running a command: its output and errors stay in English.
    static func useEnglishOnly() {
        state.withLock { $0.englishOnly = true }
    }

    /// The string for `key`, or `defaultValue` (the key when nil) when the catalog has no entry.
    static func string(_ key: String, language: String, default defaultValue: String? = nil) -> String {
        let fallback = defaultValue ?? key
        guard let bundle = bundle(for: code(language)) else { return fallback }
        return bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    /// A format string from the catalog with its arguments, in the language's locale. Plural variations
    /// in the catalog (compiled to `.stringsdict`) pick the form for the count.
    static func format(_ key: String, language: String, default defaultValue: String? = nil,
                       _ arguments: [any CVarArg]) -> String {
        let format = string(key, language: language, default: defaultValue)
        return String(format: format, locale: Locale(identifier: code(language)), arguments: arguments)
    }

    /// The folder that holds `en.lproj` and `it.lproj`: the app's resources unless a test sets another.
    static func useResources(at directory: URL?) {
        state.withLock {
            $0.resources = directory
            $0.bundles = [:]
        }
    }

    private static func bundle(for code: String) -> Bundle? {
        state.withLock { state in
            if let cached = state.bundles[code] { return cached }
            let directory = state.resources ?? Bundle.main.resourceURL
            let url = directory?.appendingPathComponent(code + ".lproj", isDirectory: true)
            let bundle = url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? Bundle(url: $0) : nil }
            state.bundles[code] = .some(bundle)
            return bundle
        }
    }

    private struct State {
        var resources: URL?
        var bundles: [String: Bundle?] = [:]
        var englishOnly = false
    }

    private final class Locked: @unchecked Sendable {
        private let lock = NSLock()
        private var value = State()

        func withLock<T>(_ body: (inout State) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }

    private static let state = Locked()
}

/// Views and commands that carry the interface language get `tr` for their strings.
@MainActor
protocol Localizing {
    var language: String { get }
}

extension Localizing {
    /// The string whose key is its English text.
    func tr(_ english: String) -> String { L10n.string(english, language: language) }

    /// The string for an explicit key, used when one English text has more than one Italian translation.
    func tr(_ english: String, key: String) -> String { L10n.string(key, language: language, default: english) }

    /// A format string (its English text is the key) with positional arguments.
    func tr(_ format: String, _ arguments: any CVarArg...) -> String {
        L10n.format(format, language: language, arguments)
    }

    var isItalian: Bool { L10n.isItalian(language) }
}
