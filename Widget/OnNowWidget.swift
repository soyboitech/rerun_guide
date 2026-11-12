import SwiftUI
import WidgetKit
import RerunGuideCore

/// The iPhone and iPad "On now" widget: what is on the guide's first channels, from the app's listings (`Shelf`). A tap
/// opens the app on that channel. No artwork and no network.
/// ponytail: no posters; the upgrade is the app downloading the shown channels' coming posters into the group container.
/// ponytail: system text styles, not the theme's faces (the widget bundles no TTFs); add them and UIAppFonts if it shows.
@main
struct OnNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rerunguide.RerunGuide.onnow", provider: Provider()) { OnNowView(entry: $0) }
            .configurationDisplayName("On now")
            .description("What is on your channels right now.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    /// The channels with what each airs at `date`; empty: off the air.
    var rows: [(row: Shelf.Row, program: Shelf.Program)] = []
    var theme: Theme = .late
}

struct Provider: TimelineProvider {
    /// A fixed sample for the gallery and the placeholder.
    static var sample: Entry {
        let now = Date.now, end = now.addingTimeInterval(32 * 60)
        let p = Shelf.Program(title: "Chrome Horizon", start: now.addingTimeInterval(-60 * 60), end: end, itemEnd: end, art: nil)
        return Entry(date: now, rows: [(Shelf.Row(id: "sample", number: 2, name: "The Vault", hue: 210, programs: [p]), p)])
    }

    func placeholder(in context: Context) -> Entry { Self.sample }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(context.isPreview ? Self.sample : entries(rows: count(context)).first ?? Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let e = entries(rows: count(context))
        completion(e.count > 1 ? Timeline(entries: e, policy: .atEnd) : Timeline(entries: [Entry(date: .now)], policy: .never))
    }

    private func count(_ context: Context) -> Int { context.family == .systemSmall ? 1 : 3 }

    /// An entry at now and at each program change of the shown rows, then off the air at the listings' end. Past 60
    /// entries the timeline stops at the 60th, so `.atEnd` reloads there instead of at the listings' end.
    private func entries(rows n: Int) -> [Entry] {
        let now = Date.now
        guard let shelf = Shelf.load(), now < shelf.until, shelf.zone == TimeZone.current.identifier, !shelf.rows.isEmpty else { return [Entry(date: now)] }
        let theme = (ThemeID(rawValue: shelf.theme) ?? .late).theme
        let rows = Array(shelf.rows.prefix(n))
        let changes = Set(rows.flatMap { $0.programs.map(\.start) }).filter { $0 > now && $0 < shelf.until }.sorted()
        return ([now] + changes.prefix(59)).map { d in Entry(date: d, rows: rows.compactMap { r in r.program(at: d).map { (r, $0) } }, theme: theme) }
            + (changes.count < 60 ? [Entry(date: shelf.until, theme: theme)] : [])
    }
}

struct OnNowView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var type

    var body: some View {
        let t = entry.theme
        Group {
            if entry.rows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Off the air").font(.headline.weight(t.headingWeight)).foregroundStyle(t.ink)
                    Text("Open Rerun Guide for today’s listings.").font(.footnote).foregroundStyle(t.dim).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if family == .systemSmall, let first = entry.rows.first {
                row(first.row, first.program).widgetURL(Shelf.tuneURL(first.row.id))
            } else {
                // Side by side: three rows stacked are taller than the widget. Larger text takes two of them.
                HStack(alignment: .top, spacing: 12) {
                    ForEach(entry.rows.prefix(type > .large ? 2 : 3), id: \.row.id) { r in
                        Link(destination: Shelf.tuneURL(r.row.id)) { row(r.row, r.program) }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        // The text follows the text size setting up to the largest standard size: past it a row is taller than the widget.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .containerBackground(for: .widget) { t.bg }
    }

    /// "12 · Front Porch", the title, a bar that fills on its own, "Ends 10:42 PM" (through the break it sits full).
    private func row(_ r: Shelf.Row, _ p: Shelf.Program) -> some View {
        let t = entry.theme
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.channel(hue: r.hue, lightness: 0.5, chroma: 0.1)).frame(width: 8, height: 8)
                Text("\(r.number) · \(r.name)").font(.caption.weight(.semibold)).foregroundStyle(t.accent).lineLimit(1)
            }
            Text(p.title).font(.subheadline.weight(t.headingWeight)).foregroundStyle(t.ink).lineLimit(2).multilineTextAlignment(.leading)   // a Link centers its label's lines
            ProgressView(timerInterval: p.start...max(p.start.addingTimeInterval(1), p.itemEnd), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(t.accent).accessibilityHidden(true)
            (Text("Ends ") + Text(p.itemEnd, style: .time)).font(.caption).foregroundStyle(t.dim).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Channel \(r.number), \(r.name). \(p.title). Ends \(p.itemEnd.formatted(date: .omitted, time: .shortened)).")
    }
}
