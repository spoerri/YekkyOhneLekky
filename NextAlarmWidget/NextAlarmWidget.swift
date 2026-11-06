import WidgetKit
import SwiftUI

@main
struct NextAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
    }
}

//Like the Clock app's Next Alarm widget, for the alarms YekkyOhneLekky schedules
struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: NextAlarmStore.widgetKind, provider: NextAlarmProvider()) { entry in
            NextAlarmView(entry: entry)
        }
        .configurationDisplayName("Next Alarm")
        .description("See when your next YekkyOhneLekky alarm will ring.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let alarm: UpcomingAlarm?
    var specialDay: UpcomingAlarm? = nil //the next special day, when the next alarm isn't for one; only the medium widget has room for it
}

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, alarm: UpcomingAlarm(date: Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: .now.addingTimeInterval(24*60*60))!, name: "Sun-Fri"),
                       specialDay: UpcomingAlarm(date: Calendar.current.startOfDay(for: .now.addingTimeInterval(4*24*60*60)), name: "Rosh Chodesh"))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        let entry = Self.entries(from: .now).first!
        completion(context.isPreview && entry.alarm == nil ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        completion(Timeline(entries: Self.entries(from: .now), policy: .atEnd))
    }

    //An entry now, one as each alarm rings (to move on to the one after it), and one at each midnight (to keep "Today"/"Tomorrow" right).
    //Only each alarm's next ring is known, so if a recurring alarm comes round again first, the app's rescheduling (e.g. from the alarm's stop button) reloads this.
    static func entries(from now: Date) -> [NextAlarmEntry] {
        let alarms = NextAlarmStore.load()
        let specialDays = NextAlarmStore.loadSpecialDays()
        var times: Set<Date> = [now]
        times.formUnion(alarms.map(\.date).filter { $0 > now })
        let calendar = Calendar.current
        var midnight = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            midnight = calendar.date(byAdding: .day, value: 1, to: midnight)!
            times.insert(midnight)
        }
        return times.sorted().map { time in
            let today = calendar.startOfDay(for: time)
            let alarm = alarms.first { $0.date > time }
            let specialDay = alarm?.isSpecial == true ? nil : specialDays.first { $0.date >= today }
            return NextAlarmEntry(date: time, alarm: alarm, specialDay: specialDay)
        }
    }
}

struct NextAlarmView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextAlarmEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    //the very next alarm, and the next special day beside it if there is one to show
    private var medium: some View {
        HStack(spacing: 16) {
            small
            if let specialDay = entry.specialDay {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    Text(specialDay.name)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    //e.g. "on Monday", "on Nov 26"
                    Text("on \(weekdayOrDate(specialDay.date))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "alarm.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Spacer(minLength: 0)
            if let alarm = entry.alarm {
                Text(day(alarm.date))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(alarm.date, format: .dateTime.hour().minute())
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(alarm.name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No Alarms")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "alarm.fill")
                    .font(.caption)
                if let alarm = entry.alarm {
                    Text(alarm.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else {
                    Text("--")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
            }
            .padding(4)
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let alarm = entry.alarm {
                Label(day(alarm.date), systemImage: "alarm.fill")
                    .font(.headline)
                    .widgetAccentable()
                Text(alarm.date, format: .dateTime.hour().minute())
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text(alarm.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("No Alarms", systemImage: "alarm.fill")
                    .font(.headline)
                    .widgetAccentable()
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inline: some View {
        if let alarm = entry.alarm {
            Text("\(Image(systemName: "alarm.fill")) \(day(alarm.date)) \(alarm.date.formatted(.dateTime.hour().minute()))")
        } else {
            Text("\(Image(systemName: "alarm.fill")) No Alarms")
        }
    }

    //the day of the week within a week from the entry's time, otherwise the short date
    private func weekdayOrDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if let week = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: entry.date)), date < week {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    //relative to the entry's time rather than now, since the entries are worked out ahead of time
    private func day(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        if calendar.isDate(date, inSameDayAs: today) {
            return String(localized: "Today")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        if let week = calendar.date(byAdding: .day, value: 7, to: today), date < week {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

#Preview(as: .systemSmall) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, alarm: UpcomingAlarm(date: .now.addingTimeInterval(20*60*60), name: "Sun-Fri"))
    NextAlarmEntry(date: .now, alarm: nil)
}

#Preview(as: .systemMedium) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, alarm: UpcomingAlarm(date: .now.addingTimeInterval(20*60*60), name: "Sun-Fri"),
                   specialDay: UpcomingAlarm(date: Calendar.current.startOfDay(for: .now.addingTimeInterval(3*24*60*60)), name: "Rosh Chodesh"))
    NextAlarmEntry(date: .now, alarm: UpcomingAlarm(date: .now.addingTimeInterval(20*60*60), name: "Sun-Fri"),
                   specialDay: UpcomingAlarm(date: Calendar.current.startOfDay(for: .now.addingTimeInterval(20*24*60*60)), name: "Thanksgiving"))
    NextAlarmEntry(date: .now, alarm: nil)
}

#Preview(as: .accessoryRectangular) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, alarm: UpcomingAlarm(date: .now.addingTimeInterval(3*24*60*60), name: "Saturday"))
}
