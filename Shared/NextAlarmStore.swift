import Foundation
import WidgetKit

//One upcoming ring, or one upcoming special day, as the Next Alarm widget shows it
nonisolated struct UpcomingAlarm: Codable, Hashable, Sendable {
    var date: Date
    var name: String
    var isSpecial = false //yom tov, rosh chodesh, a national etc., rather than a weekday or one off

    init(date: Date, name: String, isSpecial: Bool = false) {
        self.date = date
        self.name = name
        self.isSpecial = isSpecial
    }

    //tolerates what an older version saved
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        name = try container.decode(String.self, forKey: .name)
        isSpecial = try container.decodeIfPresent(Bool.self, forKey: .isSpecial) ?? false
    }
}

//The app writes the upcoming alarms here whenever it schedules; the widget extension reads them, through the shared app group
nonisolated enum NextAlarmStore {
    static let appGroup = "group.org.spoer.YekkyOhneLekky"
    static let widgetKind = "NextAlarmWidget"
    private static let alarmsKey = "upcomingAlarms"
    private static let specialDaysKey = "upcomingSpecialDays"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    //each enabled alarm's next ring, soonest first
    static func load() -> [UpcomingAlarm] {
        load(alarmsKey)
    }

    //the coming days of yom tov, rosh chodesh etc. that matter for an alarm; each date is the start of its day
    static func loadSpecialDays() -> [UpcomingAlarm] {
        load(specialDaysKey)
    }

    //only reloads the widget when something changed, since iOS budgets reloads
    static func save(_ alarms: [UpcomingAlarm], specialDays: [UpcomingAlarm]) {
        guard alarms != load() || specialDays != loadSpecialDays(),
              let alarmsData = try? JSONEncoder().encode(alarms),
              let specialDaysData = try? JSONEncoder().encode(specialDays) else {
            return
        }
        defaults?.set(alarmsData, forKey: alarmsKey)
        defaults?.set(specialDaysData, forKey: specialDaysKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private static func load(_ key: String) -> [UpcomingAlarm] {
        guard let data = defaults?.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([UpcomingAlarm].self, from: data)) ?? []
    }
}

