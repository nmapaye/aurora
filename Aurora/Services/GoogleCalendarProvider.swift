import AuroraCore
import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Google uses native OAuth + PKCE, not an API key. Registration supplies a
/// public client identifier and matching reversed-client URL scheme in Info.plist.
@MainActor
final class GoogleCalendarProvider: NSObject, CommitmentProvider, ASWebAuthenticationPresentationContextProviding {
    let providerID = CalendarProviderID.google
    private let account = "aurora.google.calendar.oauth"
    private var authSession: ASWebAuthenticationSession?
    private var token: Token?
    private var sessionGeneration = 0
    /// Calendar colors from the calendar list, so every read of an event
    /// maps it the same way.
    private var colors: [String: String] = [:]
    private struct Token: Codable { var accessToken: String; var refreshToken: String?; var expiresAt: Date }
    /// Info.plist lookup; tests inject values instead of the app bundle's.
    private let infoValue: (String) -> Any?
    var configured: Bool {
        guard let clientID, let callbackScheme, !clientID.isEmpty, !callbackScheme.isEmpty else { return false }
        let types = infoValue("CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(callbackScheme) == true }
    }
    /// A token left in the Keychain by a build that had a client ID does not
    /// count when this build has none, so an unconfigured build never calls Google.
    var connected: Bool { configured && token != nil }
    private var clientID: String? { infoValue("AuroraGoogleClientID") as? String }
    private var callbackScheme: String? { infoValue("AuroraGoogleCallbackScheme") as? String }
    override convenience init() {
        self.init(infoValue: { Bundle.main.object(forInfoDictionaryKey: $0) }, storedToken: GoogleCalendarProvider.keychainToken)
    }
    /// Test seam: Info.plist values and the stored token come from the caller.
    init(infoValue: @escaping (String) -> Any?, storedToken: (_ account: String) -> Data?) {
        self.infoValue = infoValue
        super.init()
        if let data = storedToken(account) { token = try? JSONDecoder().decode(Token.self, from: data) }
    }
    private static func keychainToken(account: String) -> Data? {
        var result: CFTypeRef?
        guard SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
    private func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    func connect() async throws {
        guard configured, let clientID, let callbackScheme else { throw CalendarActionError.unavailable }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CalendarActionError.unavailable }
        let verifier = base64URL(Data(bytes)), state = UUID().uuidString
        let redirect = "\(callbackScheme):/oauthredirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly"),
            .init(name: "code_challenge", value: base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: callbackScheme) { url, error in
                if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? CalendarActionError.unavailable) }
            }
            session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = true
            authSession = session
            if !session.start() { continuation.resume(throwing: CalendarActionError.unavailable) }
        }
        authSession = nil
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard callback.scheme == callbackScheme, query.first(where: { $0.name == "state" })?.value == state,
              let code = query.first(where: { $0.name == "code" })?.value else { throw CalendarActionError.unavailable }
        try await exchange(["client_id": clientID, "code": code, "code_verifier": verifier, "redirect_uri": redirect, "grant_type": "authorization_code"])
    }
    func disconnect() {
        token = nil
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: account] as CFDictionary)
    }
    struct CredentialDeletionFailure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Google credential deletion failed (Keychain status \(status))." }
    }
    static func deleteLocalCredentials() throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: "aurora.google.calendar.oauth"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialDeletionFailure(status: status) }
    }
    func forgetLocalSession() { sessionGeneration += 1; authSession?.cancel(); authSession = nil; token = nil }
    private func exchange(_ fields: [String: String]) async throws {
        let generation = sessionGeneration
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents(); body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard generation == sessionGeneration else { throw CalendarActionError.unavailable }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CalendarActionError.unavailable }
        struct Result: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
        let result = try JSONDecoder().decode(Result.self, from: data)
        let next = Token(accessToken: result.access_token, refreshToken: result.refresh_token ?? token?.refreshToken, expiresAt: .now.addingTimeInterval(result.expires_in))
        let bytes = try JSONEncoder().encode(next)
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account] as CFDictionary
        let status = SecItemUpdate(query, [kSecValueData: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecValueData: bytes,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil) == errSecSuccess else { throw CalendarActionError.unavailable }
        } else if status != errSecSuccess { throw CalendarActionError.unavailable }
        token = next
    }
    private func request(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil, etag: String? = nil) async throws -> Data {
        guard let existing = token else { throw CalendarActionError.unavailable }
        if existing.expiresAt < .now.addingTimeInterval(60) {
            guard let refresh = existing.refreshToken, let clientID else { throw CalendarActionError.unavailable }
            try await exchange(["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
        }
        var url = URLComponents(string: "https://www.googleapis.com/calendar/v3/\(path)")!; url.queryItems = query
        var request = URLRequest(url: url.url!); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20
        request.setValue("Bearer \(token!.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-Match") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 412 { throw CalendarActionError.stale }
        guard let status, (200..<300).contains(status) else { throw CalendarActionError.unavailable }
        return data
    }
    private func pathComponent(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
    private struct CalendarList: Decodable {
        struct Item: Decodable { let id: String; let summary: String?; let accessRole: String?; let backgroundColor: String? }
        let items: [Item]?; let nextPageToken: String?
    }
    func calendars() async throws -> [AssistantCalendar] {
        guard connected else { return [] }
        var all: [AssistantCalendar] = [], page: String?
        repeat {
            let list = try JSONDecoder().decode(CalendarList.self, from: await request(path: "users/me/calendarList", query: page.map { [.init(name: "pageToken", value: $0)] } ?? []))
            for item in list.items ?? [] { colors[item.id] = item.backgroundColor }
            all += (list.items ?? []).map { .init(id: $0.id, provider: .google, title: $0.summary ?? $0.id, writable: ["owner", "writer"].contains($0.accessRole ?? "")) }
            page = list.nextPageToken
        } while page != nil
        return all
    }
    private struct Event: Decodable {
        struct Time: Decodable { let dateTime: String?; let date: String?; let timeZone: String? }
        struct Organizer: Decodable { let isSelf: Bool?; enum CodingKeys: String, CodingKey { case isSelf = "self" } }
        struct Attendee: Decodable { let email: String? }
        let id: String; let etag: String; let summary: String?; let start: Time?; let end: Time?
        let attendees: [Attendee]?; let organizer: Organizer?; let recurringEventId: String?; let status: String?
        let location: String?; let updated: String?
    }
    private struct Events: Decodable { let items: [Event]?; let nextPageToken: String? }
    private func date(_ text: String) -> Date? {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = format.date(from: text) { return value }
        format.formatOptions = [.withInternetDateTime]; return format.date(from: text)
    }
    private func map(_ event: Event, calendarID: String, writable: Bool) -> Commitment? {
        guard event.status != "cancelled", let start = event.start, let end = event.end else { return nil }
        let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd"; format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: start.timeZone ?? TimeZone.current.identifier)
        guard let from = start.dateTime.flatMap(date) ?? start.date.flatMap(format.date), let to = end.dateTime.flatMap(date) ?? end.date.flatMap(format.date) else { return nil }
        return .init(id: event.id, calendarID: calendarID, provider: .google, title: event.summary ?? "Untitled event", start: from, end: to,
            timeZone: start.timeZone ?? TimeZone.current.identifier, revision: event.etag,
            canMove: writable && start.date == nil && (event.attendees?.isEmpty ?? true) && event.organizer?.isSelf == true, recurring: event.recurringEventId != nil,
            location: event.location?.isEmpty == false ? event.location : nil, colorHex: colors[calendarID], lastModified: event.updated.flatMap(date), allDay: start.date != nil)
    }
    func events(calendarIDs: [String], from: Date, to: Date) async throws -> [Commitment] {
        let available = try await calendars(); var all: [Commitment] = []
        let formatter = ISO8601DateFormatter()
        for id in calendarIDs {
            var page: String?
            repeat {
                var query: [URLQueryItem] = [.init(name: "timeMin", value: formatter.string(from: from)), .init(name: "timeMax", value: formatter.string(from: to)), .init(name: "singleEvents", value: "true"), .init(name: "maxResults", value: "250")]
                if let page { query.append(.init(name: "pageToken", value: page)) }
                let list = try JSONDecoder().decode(Events.self, from: await request(path: "calendars/\(pathComponent(id))/events", query: query))
                all += (list.items ?? []).compactMap { map($0, calendarID: id, writable: available.first { $0.id == id }?.writable == true) }
                page = list.nextPageToken
            } while page != nil
        }
        return all
    }
    func current(_ event: Commitment) async throws -> Commitment {
        let available = try await calendars()
        let data = try await request(path: "calendars/\(pathComponent(event.calendarID))/events/\(pathComponent(event.id))")
        guard let result = map(try JSONDecoder().decode(Event.self, from: data), calendarID: event.calendarID, writable: available.first { $0.id == event.calendarID }?.writable == true) else { throw CalendarActionError.unavailable }
        return result
    }
    func move(_ change: CalendarChange) async throws -> Commitment {
        let formatter = ISO8601DateFormatter()
        let body = try JSONSerialization.data(withJSONObject: ["start": ["dateTime": formatter.string(from: change.newStart), "timeZone": change.original.timeZone], "end": ["dateTime": formatter.string(from: change.newEnd), "timeZone": change.original.timeZone]])
        let data = try await request(path: "calendars/\(pathComponent(change.original.calendarID))/events/\(pathComponent(change.original.id))", query: [.init(name: "sendUpdates", value: "none")], method: "PATCH", body: body, etag: change.original.revision)
        guard let result = map(try JSONDecoder().decode(Event.self, from: data), calendarID: change.original.calendarID, writable: true) else { throw CalendarActionError.unavailable }
        return result
    }
}
