import Foundation
import AppIntents

@available(iOS 16.0, *)
struct AuroraDrinkEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved drink")
  static var defaultQuery = AuroraDrinkQuery()
  let id: String
  let name: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
@available(iOS 16.0, *)
struct AuroraDrinkQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [AuroraDrinkEntity] {
    (AuroraShared.read()?.drinks ?? []).filter { identifiers.contains($0.id) }.map { AuroraDrinkEntity(id:$0.id,name:$0.name) }
  }
  func suggestedEntities() async throws -> [AuroraDrinkEntity] {
    (AuroraShared.read()?.drinks ?? []).map { AuroraDrinkEntity(id:$0.id,name:$0.name) }
  }
}
@available(iOS 16.0, *)
struct LogAuroraDrink: AppIntent {
  static var title: LocalizedStringResource = "Log a drink in Aurora"
  static var description = IntentDescription("Choose a saved drink or an amount. Aurora opens for your confirmation and never logs automatically.")
  static var openAppWhenRun = true
  @Parameter(title: "Saved drink") var drink: AuroraDrinkEntity?
  @Parameter(title: "Caffeine amount (mg)") var amount: Int?
  func perform() async throws -> some IntentResult {
    guard (drink == nil) != (amount == nil) else { throw AuroraIntentError.chooseOne }
    var components = URLComponents(); components.scheme = "aurora"; components.host = "native"; components.path = "/log"
    if let drink = drink {
      guard AuroraShared.read()?.drinks.contains(where:{$0.id == drink.id}) == true else { throw AuroraIntentError.missingDrink }
      components.queryItems = [URLQueryItem(name:"drinkId", value:drink.id)]
    } else if let amount = amount, (1...1999).contains(amount) {
      components.queryItems = [URLQueryItem(name:"amount",value:String(amount))]
    } else { throw AuroraIntentError.invalidAmount }
    guard let url = components.url else { throw AuroraIntentError.invalidAmount }
    try AuroraInbox.append(url.absoluteString)
    return .result()
  }
}
@available(iOS 16.0, *)
struct AuroraStatusIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Aurora status"
  static var description = IntentDescription("Read a timestamped local snapshot. Open Aurora to refresh stale or unavailable information.")
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let text: String
    if let s = AuroraShared.read() {
      let updated = AuroraShared.date(s.generatedAt).formatted(date:.abbreviated,time:.shortened)
      if s.isFresh() {
        let logged = s.loggedMg.map { "Today's logged caffeine: \(Int($0.rounded())) mg." } ?? "Today's intake is unavailable; no intake or caffeine-free day is recorded."
        let cutoff = s.cutoff.map { "Next chosen cutoff: \(AuroraShared.date($0).formatted(date:.abbreviated,time:.shortened))." } ?? "Cutoff unavailable."
        text = "\(logged) \(cutoff) Updated \(updated)."
      } else { text = "Aurora status is stale. Last updated \(updated). Open Aurora to refresh." }
    } else { text = "Aurora status is unavailable. Open Aurora to set up and refresh its local snapshot." }
    return .result(value:text,dialog:IntentDialog(stringLiteral:text))
  }
}
@available(iOS 16.0, *)
struct AuroraShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent:LogAuroraDrink(),phrases:["Log a drink in \(.applicationName)"],shortTitle:"Log a drink",systemImageName:"cup.and.saucer")
    AppShortcut(intent:AuroraStatusIntent(),phrases:["Get my \(.applicationName) status"],shortTitle:"Aurora status",systemImageName:"chart.bar")
  }
}
enum AuroraIntentError: Error, LocalizedError {
  case chooseOne, invalidAmount, missingDrink, unavailable, queueFull
  var errorDescription: String? {
    switch self {
    case .unavailable: return "Aurora local storage is unavailable."
    case .queueFull: return "Review pending Aurora drinks before adding another Shortcut request."
    case .chooseOne: return "Choose either a saved drink or a caffeine amount."
    case .invalidAmount: return "Caffeine amount must be a whole number between 1 and 1999 mg."
    case .missingDrink: return "This saved drink is unavailable. Open Aurora and choose an available drink."
    }
  }
}
