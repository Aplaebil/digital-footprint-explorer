import SwiftUI
import WidgetKit

// [01] A widget entry is a view of a saved result at a given time, not a new Screen Time reading.
struct GardenWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetSnapshotReadResult
    var isPreview = false
}

struct GardenWidgetProvider: TimelineProvider {
    // [02] The gallery needs a sample garden before a real entry exists. It stays labelled as a preview.
    func placeholder(in context: Context) -> GardenWidgetEntry {
        let now = Date()
        return GardenWidgetEntry(date: now, data: .saved(.preview(on: now)), isPreview: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (GardenWidgetEntry) -> Void) {
        let now = Date()
        // [03] Gallery examples never enter shared storage or replace a person's saved result.
        let data: WidgetSnapshotReadResult = context.isPreview ? .saved(.preview(on: now)) : WidgetSnapshotStorage.configured().read()
        completion(GardenWidgetEntry(date: now, data: data, isPreview: context.isPreview))
    }
    // [04] Read the summary the app already saved; the widget never requests protected activity itself.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GardenWidgetEntry>) -> Void) {
        let now = Date()
        let entry = GardenWidgetEntry(date: now, data: WidgetSnapshotStorage.configured().read())
        // [05] Midnight changes the date label, not the saved result. WidgetKit sets the schedule.
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(nextDay)))
    }
}

@main
// [06] Offer the two supported sizes, both opening the same Today route.
struct FootprintGardenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GardenWidgetSnapshot.widgetKind, provider: GardenWidgetProvider()) { entry in
            GardenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Your garden")
        .description("Keep your garden nearby. See your last saved estimate, then tap to review your day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct GardenWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GardenWidgetEntry
    var body: some View {
        GardenWidgetView(data: entry.data, family: family, date: entry.date, isPreview: entry.isPreview)
    }
}
