import WidgetKit
import SwiftUI
import DesignSystem

// MARK: - Timeline

struct GrooveEntry: TimelineEntry {
    let date: Date
    let movements: [Movement]
    /// movement id string → sets done today.
    let done: [String: Int]

    var target: Int { movements.reduce(0) { $0 + $1.setsPerDay } }
    var remaining: Int { movements.reduce(0) { $0 + max(0, $1.setsPerDay - setsDone($1)) } }
    var progress: Double {
        guard target > 0 else { return 0 }
        return Double(target - remaining) / Double(target)
    }
    var isComplete: Bool { !movements.isEmpty && remaining == 0 }

    func setsDone(_ movement: Movement) -> Int {
        done[movement.id.uuidString] ?? 0
    }

    static var placeholder: GrooveEntry {
        GrooveEntry(
            date: .now,
            movements: Movement.starters,
            done: [Movement.starters[0].id.uuidString: 2]
        )
    }
}

struct GrooveProvider: TimelineProvider {
    func placeholder(in context: Context) -> GrooveEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (GrooveEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GrooveEntry>) -> Void) {
        // The app and the log intent reload timelines on every change;
        // the scheduled refresh just rolls the date over at midnight.
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400)
        completion(Timeline(entries: [currentEntry()], policy: .after(midnight)))
    }

    private func currentEntry() -> GrooveEntry {
        let store = GrooveStore()
        return GrooveEntry(
            date: .now,
            movements: store.movements,
            done: store.days[store.todayKey] ?? [:]
        )
    }
}

// MARK: - Widget

struct GrooveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GrooveWidget", provider: GrooveProvider()) { entry in
            GrooveWidgetView(entry: entry)
                .dsTheme(.groove)
        }
        .configurationDisplayName("Today's sets")
        .description("Your movements at a glance. Tap one to log a set.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

@main
struct GrooveWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GrooveWidget()
    }
}

// MARK: - Views

struct GrooveWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GrooveEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .systemMedium:
            MediumWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.dsBackground }
        default:
            SmallWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.dsBackground }
        }
    }
}

private func remainingCaption(_ remaining: Int) -> String {
    remaining == 1 ? "1 set to go" : "\(remaining) sets to go"
}

struct SmallWidgetView: View {
    @Environment(\.dsTheme) private var theme
    let entry: GrooveEntry

    var body: some View {
        VStack(spacing: DSSpace.s) {
            ZStack {
                ProgressRing(progress: entry.progress, lineWidth: 8)
                    .frame(width: 76, height: 76)
                if entry.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accent)
                } else {
                    Text("\(entry.remaining)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.dsInk)
                }
            }
            Text(entry.isComplete ? "Done for today" : remainingCaption(entry.remaining))
                .font(.dsCaption)
                .foregroundStyle(Color.dsInkSecondary)
        }
    }
}

struct MediumWidgetView: View {
    @Environment(\.dsTheme) private var theme
    let entry: GrooveEntry

    var body: some View {
        HStack(spacing: DSSpace.m) {
            ZStack {
                ProgressRing(progress: entry.progress, lineWidth: 8)
                    .frame(width: 72, height: 72)
                if entry.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accent)
                } else {
                    Text("\(entry.remaining)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.dsInk)
                }
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: DSSpace.xs) {
                ForEach(entry.movements.prefix(4)) { movement in
                    movementButton(movement)
                }
            }
        }
    }

    private func movementButton(_ movement: Movement) -> some View {
        let done = entry.setsDone(movement)
        let complete = done >= movement.setsPerDay
        return Button(intent: LogSetIntent(movementID: movement.id.uuidString)) {
            HStack(spacing: DSSpace.s) {
                Image(systemName: movement.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(complete ? .white : theme.accent)
                    .frame(width: 14)
                Text(movement.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(complete ? .white : Color.dsInk)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(done)/\(movement.setsPerDay)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.dsInkSecondary)
                }
            }
            .padding(.horizontal, DSSpace.s)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(
                complete ? theme.accent : Color.dsSurface,
                in: .rect(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CircularWidgetView: View {
    let entry: GrooveEntry

    var body: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "figure.strengthtraining.functional")
        } currentValueLabel: {
            if entry.isComplete {
                Image(systemName: "checkmark")
            } else {
                Text("\(entry.remaining)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    GrooveWidget()
} timeline: {
    GrooveEntry.placeholder
    GrooveEntry(date: .now, movements: Movement.starters, done: [:])
}

#Preview("Medium", as: .systemMedium) {
    GrooveWidget()
} timeline: {
    GrooveEntry.placeholder
}

#Preview("Circular", as: .accessoryCircular) {
    GrooveWidget()
} timeline: {
    GrooveEntry.placeholder
}
