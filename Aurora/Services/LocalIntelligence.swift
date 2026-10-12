import AuroraCore
import Foundation
import FoundationModels

@MainActor
protocol LocalIntentModel {
    var name: String { get }
    func classify(_ text: String) async throws -> AssistantIntent
}

enum IntelligenceFailure: LocalizedError {
    case unavailable, invalidOutput, localServerUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple's local model isn't available on this device. Quick actions still work."
        case .invalidOutput: "I couldn't confidently understand that. Try a quick action or say one task at a time."
        case .localServerUnavailable: "The local Mac model isn't reachable. Quick actions still work."
        }
    }
}

final class AppleIntentModel: LocalIntentModel {
    private var prepared: ((String) async throws -> AssistantIntent)?
    private var preparedAt: Date?

    /// Warm one blank classifier session while the person composes. It is consumed
    /// once so previous requests never become context for a later classification.
    func prewarm() {
        guard prepared == nil, #available(iOS 26.0, *), Self.available else { return }
        let session = LanguageModelSession(instructions: AssistantPlanner.modelInstructions)
        session.prewarm()
        preparedAt = .now
        prepared = { text in
            let response = try await session.respond(to: text, options: GenerationOptions(temperature: 0, maximumResponseTokens: 30))
            try Task.checkCancellation()
            return AssistantPlanner.modelIntent(response.content)
        }
    }

    func releasePreparedSession() { prepared = nil; preparedAt = nil }
    let name = "Apple on-device model"
    static var available: Bool {
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        return false
    }
    func classify(_ text: String) async throws -> AssistantIntent {
        guard #available(iOS 26.0, *), Self.available else { throw IntelligenceFailure.unavailable }
        if let ready = prepared, let date = preparedAt, Date.now.timeIntervalSince(date) >= 1 {
            releasePreparedSession()
            return try await ready(text)
        }
        // A rapid send never waits for warmup. Apple recommends at least one
        // second between prewarm and responding on that session.
        releasePreparedSession()
        let session = LanguageModelSession(instructions: AssistantPlanner.modelInstructions)
        let response = try await session.respond(to: text, options: GenerationOptions(temperature: 0, maximumResponseTokens: 30))
        try Task.checkCancellation()
        let intent = AssistantPlanner.modelIntent(response.content)
        return intent
    }
}

/// Loopback only: the simulator may use a model running on its host Mac.
/// No cloud endpoint, key, global Ollama setting, or LAN exposure is accepted.
struct MacIntentModel: LocalIntentModel {
    let model: String
    var name: String { "Mac local · \(model)" }
    func classify(_ text: String) async throws -> AssistantIntent {
        #if targetEnvironment(simulator)
        guard !model.lowercased().contains("cloud") else { throw IntelligenceFailure.localServerUnavailable }
        var inspection = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/show")!)
        inspection.httpMethod = "POST"; inspection.timeoutInterval = 10
        inspection.setValue("application/json", forHTTPHeaderField: "Content-Type")
        inspection.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
        let (metadata, inspected) = try await URLSession.shared.data(for: inspection)
        guard (inspected as? HTTPURLResponse)?.statusCode == 200,
              let details = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              details["remote_host"] == nil, details["remote_model"] == nil,
              let info = details["model_info"] as? [String: Any], !info.isEmpty else {
            throw IntelligenceFailure.localServerUnavailable
        }
        struct Payload: Encodable {
            struct Message: Encodable { let role: String; let content: String }
            let model: String
            let messages: [Message]
            let stream = false
            let think = false
            let options = ["temperature": 0, "num_predict": 40]
        }
        struct Reply: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(model: model, messages: [
            .init(role: "system", content: AssistantPlanner.modelInstructions), .init(role: "user", content: String(text.prefix(2000)))
        ]))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw IntelligenceFailure.localServerUnavailable }
        return AssistantPlanner.modelIntent(try JSONDecoder().decode(Reply.self, from: data).message.content)
        #else
        throw IntelligenceFailure.localServerUnavailable
        #endif
    }
}
