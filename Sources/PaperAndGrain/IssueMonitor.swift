import Foundation
import Observation

/// Keeps the preflight result of the open book current. Each change to the book restarts a short
/// wait; only when the book has been quiet for `delay` does the check run, off the main thread.
/// A run that a newer change overtakes is cancelled and never published.
@MainActor @Observable
final class IssueMonitor {
    /// The latest result; nil until the first run finishes.
    private(set) var report: BookPDF.Preflight?

    typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias Check = @Sendable (Book, URL?, BookPDF.Profile) -> BookPDF.Preflight

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private let check: Check
    @ObservationIgnored private var task: Task<Void, Never>?

    /// `sleep` and `check` are injected so tests can control the clock and count the runs.
    init(delay: Duration = .milliseconds(600),
         sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
         check: @escaping Check = { BookPDF.preflight($0, directory: $1, profile: $2) }) {
        self.delay = delay
        self.sleep = sleep
        self.check = check
    }

    /// Runs the check after the quiet period, or at once for the first look at a book.
    func bookChanged(_ book: Book, directory: URL?, profile: BookPDF.Profile = .print, immediately: Bool = false) {
        task?.cancel()
        let delay = immediately ? nil : delay
        let sleep = sleep
        let check = check
        task = Task { [weak self] in
            if let delay {
                do { try await sleep(delay) } catch { return }
            }
            if Task.isCancelled { return }
            let found = await Task.detached(priority: .utility) { check(book, directory, profile) }.value
            if Task.isCancelled { return }
            self?.report = found
        }
    }

    /// Waits for the run in progress; for tests.
    func settle() async {
        await task?.value
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
