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
    /// Extra warnings found on the main actor, such as the spelling check, which yields between texts.
    typealias Extra = @MainActor @Sendable (Book) async -> [BookPDF.PreflightIssue]

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private let check: Check
    @ObservationIgnored private let extra: Extra?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Fills the gamut estimates a run lacked, in the background; edits do not cancel it.
    @ObservationIgnored let estimator = GamutEstimator()
    /// The inputs of the latest run, to check again when estimates arrive.
    @ObservationIgnored private var last: (book: Book, directory: URL?, profile: BookPDF.Profile)?

    /// `sleep` and `check` are injected so tests can control the clock and count the runs.
    init(delay: Duration = .milliseconds(600),
         sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
         check: @escaping Check = { BookPDF.preflight($0, directory: $1, profile: $2) },
         extra: Extra? = nil) {
        self.extra = extra
        self.delay = delay
        self.sleep = sleep
        self.check = check
    }

    /// Runs the check after the quiet period, or at once for the first look at a book.
    func bookChanged(_ book: Book, directory: URL?, profile: BookPDF.Profile = .print, immediately: Bool = false) {
        task?.cancel()
        last = (book, directory, profile)
        let delay = immediately ? nil : delay
        let sleep = sleep
        let check = check
        let extra = extra
        task = Task { [weak self] in
            if let delay {
                do { try await sleep(delay) } catch { return }
            }
            if Task.isCancelled { return }
            let work = Task.detached(priority: .utility) { check(book, directory, profile) }
            // An overtaken run also cancels the check itself, which stops at the next page.
            let found = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            if Task.isCancelled { return }
            var merged = found
            if let extra {
                merged.warnings += await extra(book)
                if Task.isCancelled { return }
            }
            self?.report = merged
            // Photos without a cached gamut estimate are measured in the background; the list is checked
            // again as results arrive, and the other issues are already published.
            if !found.pendingGamut.isEmpty, let estimator = self?.estimator {
                await estimator.enqueue(found.pendingGamut) { [weak self] in
                    await self?.recheck()
                }
            }
        }
    }

    /// Checks the latest book again at once, when background estimates have arrived.
    func recheck() {
        guard let last else { return }
        bookChanged(last.book, directory: last.directory, profile: last.profile, immediately: true)
    }

    /// Waits for the run in progress; for tests.
    func settle() async {
        await task?.value
    }

    func stop() {
        task?.cancel()
        task = nil
        last = nil
        let estimator = estimator
        Task { await estimator.cancel() }
    }
}
