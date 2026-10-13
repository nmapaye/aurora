import AuroraCore
import Foundation

/// Session-only classifications, never answers, records, drafts, or tool results.
/// Exact text and model identity prevent a correction or provider change from
/// reusing another request's interpretation. No persistence or background work.
struct IntentCache {
    private struct Entry {
        let text: String
        let model: String
        let intent: AssistantIntent
        let expires: Date
    }
    private var entries: [Entry] = []
    private let capacity: Int
    private let lifetime: TimeInterval

    init(capacity: Int = 32, lifetime: TimeInterval = 300) {
        self.capacity = max(0, capacity)
        self.lifetime = max(0, lifetime)
    }

    mutating func lookup(_ text: String, model: String, now: Date = .now) -> AssistantIntent? {
        entries.removeAll { $0.expires <= now }
        guard let index = entries.firstIndex(where: { $0.text == text && $0.model == model }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.intent
    }

    mutating func insert(_ intent: AssistantIntent, text: String, model: String, now: Date = .now) {
        guard intent != .unsupported, capacity > 0 else { return }
        entries.removeAll { $0.expires <= now || ($0.text == text && $0.model == model) }
        entries.append(Entry(text: text, model: model, intent: intent, expires: now.addingTimeInterval(lifetime)))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    mutating func clear() { entries.removeAll() }
}
