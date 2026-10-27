import Foundation
import Testing

/// Full Keyboard Access, Switch Control and Voice Control reach real
/// controls (Button, Toggle, TextField…). A bare tap or drag gesture is
/// invisible to them, so every gesture in the app's source must be listed
/// here with how a keyboard or assistive user reaches the same action.
struct GestureOnlyControlTests {
    /// File name and the gesture's line, trimmed, with the reason it's fine.
    static let allowed: [String: String] = [
        "AssistantView.swift|.onTapGesture { focused.wrappedValue = true }":
            "Widens the composer's tap area; the text field itself takes keyboard focus.",
        "WelcomeView.swift|.onTapGesture(perform: onSkip)":
            "The overlay is a button to accessibility (isButton trait and an accessibilityAction that skips).",
        "ReactionTouchSurface.swift|override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {":
            "Space or Return answers through pressesBegan; activating the area answers through accessibilityActivate.",
    ]

    static let patterns = [".onTapGesture", ".onLongPressGesture", "TapGesture(", "LongPressGesture(", "DragGesture(", "SpatialTapGesture(", "func touchesBegan"]

    @Test func everyGestureHasAKeyboardAndAssistivePath() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Aurora")
        let files = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        var found: Set<String> = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///"), Self.patterns.contains(where: { trimmed.contains($0) }) else { continue }
                let key = "\(file.lastPathComponent)|\(trimmed)"
                found.insert(key)
                #expect(Self.allowed[key] != nil, "Gesture without a keyboard or assistive path: \(key)")
            }
        }
        #expect(!found.isEmpty, "No Swift sources found under \(app.path)")
        for stale in Set(Self.allowed.keys).subtracting(found) {
            Issue.record("Listed but no longer in the source: \(stale)")
        }
    }
}
