import Foundation
import Testing
@testable import Aurora

@MainActor
@Suite struct GoogleCalendarProviderTests {
    /// A token as a build with a Google client ID would have saved it.
    private var staleToken: Data { Data(#"{"accessToken":"stale-dev-token","refreshToken":"stale-refresh","expiresAt":0}"#.utf8) }
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
