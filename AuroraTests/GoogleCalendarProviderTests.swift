import AuroraCore
import Foundation
import Testing
@testable import Aurora

@MainActor
@Suite struct GoogleCalendarProviderTests {
    /// A token as a build with a Google client ID would have saved it.
    private var staleToken: Data { Data(#"{"accessToken":"stale-dev-token","refreshToken":"stale-refresh","expiresAt":0}"#.utf8) }
    /// An unexpired token, so request() would not need a refresh first.
    private var liveToken: Data { Data(#"{"accessToken":"stale-dev-token","expiresAt":2000000000}"#.utf8) }
    private var configuredInfo: [String: Any] { [
        "AuroraGoogleClientID": "fixture.apps.googleusercontent.com",
        "AuroraGoogleCallbackScheme": "com.googleusercontent.apps.fixture",
        "CFBundleURLTypes": [["CFBundleURLSchemes": ["com.googleusercontent.apps.fixture"]]]
    ] }

    /// v0.1.0 ships without a Google client ID. A device that still holds a
    /// Keychain token from a dev build must not count as connected, so the
    /// Release build never calls Google.
    @Test func unconfiguredProviderWithStoredTokenIsNotConnected() async throws {
        var requestedAccount: String?
        let provider = GoogleCalendarProvider(infoValue: { _ in nil }, storedToken: { requestedAccount = $0; return staleToken })
        #expect(requestedAccount == "aurora.google.calendar.oauth")
        #expect(!provider.configured)
        #expect(!provider.connected)
        #expect(try await provider.calendars().isEmpty)
    }

    /// Every Google call is gated in the provider, not only by callers. The
    /// token is unexpired, so on the old guard request() would go straight to
    /// the Calendar API; the recording protocol answers any Google request
    /// locally so no test can reach the network, and the fixed code must not
    /// send one at all.
    @Test func unconfiguredProviderWithStoredTokenMakesNoGoogleRequest() async throws {
        let provider = GoogleCalendarProvider(infoValue: { _ in nil }, storedToken: { _ in liveToken })
        URLProtocol.registerClass(RecordingGoogleProtocol.self)
        defer { URLProtocol.unregisterClass(RecordingGoogleProtocol.self) }
        RecordingGoogleProtocol.reset()
        await #expect(throws: CalendarActionError.unavailable) {
            try await provider.events(calendarIDs: ["primary"], from: .now, to: .now.addingTimeInterval(3600))
        }
        #expect(RecordingGoogleProtocol.requested.isEmpty)
    }

    /// Control: the same stored token does count once the build is configured,
    /// so the test above fails for the right reason.
    @Test func configuredProviderWithStoredTokenIsConnected() {
        let info = configuredInfo
        let provider = GoogleCalendarProvider(infoValue: { info[$0] }, storedToken: { _ in staleToken })
        #expect(provider.configured)
        #expect(provider.connected)
    }

    @Test func configuredProviderWithoutTokenIsNotConnected() {
        let info = configuredInfo
        let provider = GoogleCalendarProvider(infoValue: { info[$0] }, storedToken: { _ in nil })
        #expect(provider.configured && !provider.connected)
    }
}

/// Answers Google requests locally with 401 and records them, so a test never
/// reaches the network even when the code under test would call Google.
final class RecordingGoogleProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var urls: [URL] = []
    static func reset() { lock.lock(); urls = []; lock.unlock() }
    static var requested: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "googleapis.com" || host.hasSuffix(".googleapis.com") || host.hasSuffix(".google.com")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil) else { return }
        Self.lock.lock(); Self.urls.append(url); Self.lock.unlock()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
