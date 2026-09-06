import SwiftUI
import WidgetKit
import ActivityKit

struct AuroraEntry: TimelineEntry { let date: Date; let snapshot: AuroraSnapshot? }
struct AuroraProvider: TimelineProvider {
  func placeholder(in context: Context) -> AuroraEntry { AuroraEntry(date: Date(), snapshot: nil) }
  func getSnapshot(in context: Context, completion: @escaping (AuroraEntry) -> Void) { completion(AuroraEntry(date: Date(), snapshot: context.isPreview ? nil : AuroraShared.read())) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<AuroraEntry>) -> Void) {
    let now = Date(), snapshot = AuroraShared.read()
    var entries = [AuroraEntry(date: now, snapshot: snapshot)]
    if let snapshot = snapshot, snapshot.isFresh(at: now) { entries.append(AuroraEntry(date: AuroraShared.date(snapshot.expiresAt), snapshot: snapshot)) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
  }
}
struct AuroraSummaryView: View {
  let entry: AuroraEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Aurora").font(.headline)
      if let s = entry.snapshot {
        if s.isFresh(at: entry.date) {
          Text(s.loggedMg.map { "Logged \(Int($0.rounded())) mg" } ?? "No intake recorded")
          Text(s.activeMg.map { "Est. active \(Int($0.rounded())) mg" } ?? "Active estimate unavailable")
          if let bed = s.nextBedtime { Text("Bedtime \(AuroraShared.date(bed), style: .time)") }
        } else { Text("Snapshot out of date"); Text("Open Aurora to refresh") }
        Text("Updated \(AuroraShared.date(s.generatedAt), style: .time)").font(.caption2)
      } else { Text("Open Aurora to set up your summary") }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
      .widgetURL(URL(string: "aurora://native/summary"))
  }
}
struct AuroraHomeWidget: Widget {
  let kind = "AuroraHome"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: AuroraProvider()) { entry in
      if #available(iOSApplicationExtension 17.0, *) { AuroraSummaryView(entry: entry).containerBackground(.background, for: .widget) }
      else { AuroraSummaryView(entry: entry) }
    }.configurationDisplayName("Aurora summary").description("Logged caffeine, a model estimate and planned bedtime.").supportedFamilies([.systemSmall,.systemMedium])
  }
}
@available(iOSApplicationExtension 16.0, *)
struct AuroraLockView: View {
  @Environment(\.widgetFamily) var family
  let entry: AuroraEntry
  let cutoff: Bool
  var value: String {
    guard let s=entry.snapshot, s.showLockValues else {return "Hidden"}
    guard s.isFresh(at:entry.date) else {return "Open app"}
    if cutoff, let date=s.cutoff {return AuroraShared.date(date).formatted(date:.omitted,time:.shortened)}
    if !cutoff, let mg=s.activeMg {return "~\(Int(mg.rounded())) mg"}
    return "No data"
  }
  var body: some View {
    Group {
      if family == .accessoryInline { Text("\(Image(systemName:cutoff ? "clock":"cup.and.saucer")) \(cutoff ? "Cutoff":"Caffeine") \(value)") }
      else { VStack { Image(systemName:cutoff ? "clock":"cup.and.saucer"); Text(value) } }
    }.privacySensitive().widgetURL(URL(string:"aurora://native/summary"))
  }
}
@available(iOSApplicationExtension 16.0, *)
struct AuroraLockWidget: Widget {
  let kind: String
  let cutoff: Bool
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: AuroraProvider()) { entry in
      if #available(iOSApplicationExtension 17.0, *) { AuroraLockView(entry:entry,cutoff:cutoff).containerBackground(.background,for:.widget) }
      else { AuroraLockView(entry:entry,cutoff:cutoff) }
    }.configurationDisplayName(cutoff ? "Aurora cutoff" : "Aurora caffeine").description("Personal values are hidden until enabled in Aurora.").supportedFamilies([.accessoryCircular,.accessoryRectangular,.accessoryInline])
  }
}
@available(iOSApplicationExtension 16.2, *)
struct AuroraNapWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AuroraNapAttributes.self) { context in
      VStack(alignment:.leading) {
        Text("Aurora nap timer").font(.headline)
        Text(context.state.startedAt, style:.timer).monospacedDigit()
        Text("Open Aurora to finish and confirm sleep").font(.caption)
      }.padding().widgetURL(URL(string:"aurora://native/nap"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Text("Nap timer") }
        DynamicIslandExpandedRegion(.trailing) { Text(context.state.startedAt,style:.timer).monospacedDigit() }
        DynamicIslandExpandedRegion(.bottom) { Text("Open Aurora to finish and confirm") }
      } compactLeading: { Image(systemName:"moon.zzz") } compactTrailing: { Text(context.state.startedAt,style:.timer).monospacedDigit().frame(width:45) } minimal: { Image(systemName:"moon.zzz") }
      .widgetURL(URL(string:"aurora://native/nap"))
    }
  }
}
@main
struct AuroraWidgetBundle: WidgetBundle {
  var body: some Widget {
    AuroraHomeWidget()
    if #available(iOSApplicationExtension 16.0, *) {
      AuroraLockWidget(kind:"AuroraLockCaffeine",cutoff:false)
      AuroraLockWidget(kind:"AuroraLockCutoff",cutoff:true)
    }
    if #available(iOSApplicationExtension 16.2, *) { AuroraNapWidget() }
  }
}
