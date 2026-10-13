import Foundation

/// Runs one refresh at a time and applies its result only if nothing has
/// invalidated it meanwhile. Callers that arrive while a refresh is running
/// share it instead of starting another. `invalidate()` (on erase, sign-out
/// or a settings change) cancels the running fetch and makes any late result
/// a no-op, even when the fetch ignores cancellation.
@MainActor
public final class RefreshCoordinator<Value: Sendable> {
    public enum Outcome: Equatable, Sendable {
        case applied
        case failed(String)
        /// Invalidated before it could apply; nothing changed.
        case discarded
    }

    public private(set) var generation = 0
    public var isRefreshing: Bool { running != nil }

    private let fetch: @Sendable () async throws -> Value
    private let apply: @MainActor (Value) -> Void
    private var running: (generation: Int, task: Task<Outcome, Never>)?

    public init(fetch: @escaping @Sendable () async throws -> Value, apply: @escaping @MainActor (Value) -> Void) {
        self.fetch = fetch
        self.apply = apply
    }

    @discardableResult
    public func refresh() async -> Outcome {
        if let running, running.generation == generation {
            return await running.task.value
        }
        let started = generation
        let fetch = self.fetch
        let task = Task { @MainActor [weak self] () -> Outcome in
            let outcome: Outcome
            do {
                let value = try await fetch()
                if let self, started == self.generation, !Task.isCancelled {
                    self.apply(value)
                    outcome = .applied
                } else {
                    outcome = .discarded
                }
            } catch {
                let current = self.map { started == $0.generation && !Task.isCancelled } ?? false
                outcome = current && !(error is CancellationError) ? .failed(error.localizedDescription) : .discarded
            }
            if let self, self.running?.generation == started { self.running = nil }
            return outcome
        }
        running = (started, task)
        return await task.value
    }

    /// Cancels the running refresh and discards its result whenever it lands.
    public func invalidate() {
        generation += 1
        running?.task.cancel()
        running = nil
    }
}
