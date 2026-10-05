import Foundation
import SwiftData
import SwiftUI
import AVFoundation
import AlarmKit
import OSLog

@Model
class AlarmModel {
    @Attribute(.unique) var name: String
    var ids: Array<UUID>
    var hour: Int
    var minute: Int
    var maybeDayToFire: String //yyyy-MM-dd in local time
    var nextDayToFire: String //yyyy-MM-dd in local time; differs from maybeDayToFire when the alarm is overridden on maybeDayToFire
    var isEnabled: Bool
    var isExtra: Bool
    var isGrouped: Bool
    var daysOfWeek: Set<String>
    var selectedSound: String?
    var createdAt: Date
    var duration: TimeInterval?
    var repetitions: Int
    var repetitionDelay: TimeInterval
    //stored as a plain Int so an unknown/removed enum case can't crash decoding; use alarmType instead
    @Attribute(originalName: "alarmType") var alarmTypeRaw: Int
    
    init(name: String, alarmType: AlarmType, ids: Array<UUID> = Array(), daysOfWeek: Set<String> = Set(), hour: Int, minute: Int, maybeDayToFire: String, nextDayToFire: String, isEnabled: Bool = true, isExtra: Bool = false, isGrouped: Bool = false, selectedSound: String? = nil, duration: TimeInterval? = 60, repetitions: Int = 2, repetitionDelay: TimeInterval = 240) {
        self.name = name
        self.ids = ids
        self.hour = hour
        self.minute = minute
        self.maybeDayToFire = maybeDayToFire
        self.nextDayToFire = nextDayToFire
        self.isEnabled = isEnabled
        self.isExtra = isExtra
        self.isGrouped = isGrouped
        self.daysOfWeek = daysOfWeek
        self.createdAt = Date()
        self.selectedSound = selectedSound
        self.duration = duration
        self.repetitions = repetitions
        self.repetitionDelay = repetitionDelay
        self.alarmTypeRaw = alarmType.rawValue
    }
    
    var alarmType: AlarmType {
        get {
            if let type = AlarmType(rawValue: alarmTypeRaw) {
                return type
            }
            AlarmLogger.shared.error("unknown alarmType \(alarmTypeRaw) for \(name), treating as explicit")
            return .explicit
        }
        set {
            alarmTypeRaw = newValue.rawValue
        }
    }
    
    //a day that never comes, for an alarm whose day hasn't been worked out yet
    nonisolated static let never = "9999-12-31"
    
    //gregorian regardless of the user's calendar setting, so the stored days are always yyyy-MM-dd
    nonisolated private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        return calendar
    }
    
    //the yyyy-MM-dd day that an instant falls on, in local time
    nonisolated static func day(_ date: Date) -> String {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    
    nonisolated static func addingDays(_ day: String, _ n: Int) -> String {
        return AlarmModel.day(gregorian.date(byAdding: .day, value: n, to: date(day))!)
    }
    
    nonisolated static func addingYears(_ day: String, _ n: Int) -> String {
        return AlarmModel.day(gregorian.date(byAdding: .year, value: n, to: date(day))!)
    }
    
    //start of that day in local time; only for handing a day to APIs that need a Date
    nonisolated static func date(_ day: String) -> Date {
        let calendar = gregorian
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            AlarmLogger.shared.error("bad day \(day)")
            return Date.distantFuture
        }
        return date
    }
    
    //overridden on maybeDayToFire by another alarm that day, so it next fires on nextDayToFire
    var isOverridden: Bool {
        return maybeDayToFire != nextDayToFire
    }
    
    var timeString: String {
//        if let earliest = getEarliestTimeIfEarlier() {
//            return String(format: "%02d", earliest[0])+":"+String(format: "%02d", earliest[1])
//        }
        return String(format: "%02d", hour)+":"+String(format: "%02d", minute)
    }
    
    private func getEarliestTimeIfEarlier(_ now: Date) -> [Int]? {
        if let earliest = AlarmLogic.getEarliest(now, nextDayToFire) {
            if let earliestOffset = Calendar.current.date(byAdding: .minute, value: -30, to: earliest) { //TODO expose the config
                let earliestMinute = Calendar.current.component(.minute, from: earliestOffset)
                let earliestHour = Calendar.current.component(.hour, from: earliestOffset)
                if earliestHour > hour || (earliestHour == hour && earliestMinute > minute) {
                    return [earliestHour, earliestMinute]
                }
            }
        }
        return nil
    }
    
    func getAlarmDateAndTime() throws -> Date {
//        if let earliest = getEarliestTimeIfEarlier() {
//            return try getAlarmDate(nextDayToFire, earliest[0], earliest[1])
//        }
        return try getAlarmDateAndTime(nextDayToFire)
    }
    
    func getAlarmDateAndTime(_ day: String) throws -> Date {
        guard let fullDate = Calendar.current.date(bySettingHour: hour, minute: minute, second:0, of: AlarmModel.date(day)) else { throw AlarmError.ugh }
        return fullDate
    }
    
    func isDue(_ now: Date) throws -> Bool {
        return try getAlarmDateAndTime(maybeDayToFire) <= now
    }
    
    //this whole function is not strictly necessary, b/c AlarmLogic.scheduleNext cancels anything unexpected
    func unschedule() throws {
        var scheduled = Dictionary<UUID, String>()
        for alarm in try AlarmLogic.Manager.alarms {
            if case let .fixed(date) = alarm.schedule {
                scheduled[alarm.id] = date.formatted()
            } else {
                AlarmLogger.shared.info("unsched not fixed?!: \(alarm.id)") //app only uses fixed!
            }
        }
        var expiredCount = 0
        for id in ids {
            do {
                if let d = scheduled[id] {
                    AlarmLogger.shared.info("unsched \(d)")
                    try AlarmLogic.Manager.cancel(id: id)
                } else {
                    expiredCount += 1
                }
                ids.removeAll(where: { $0 == id }) //if there was an exception, try removing again next time
            } catch {
                AlarmLogger.shared.error("could not unschedule \(id)!")
            }
        }
        
        if expiredCount > 0 {
            AlarmLogger.shared.info("unsched \(expiredCount) expired")
        }
    }
    
    static func nameFromDaysOfWeek(_ daysOfWeek: Set<String>) -> String {
        if daysOfWeek.count == 6 {
            return "Sun-Fri" //otherwise it's too long
        } else if daysOfWeek.count == 1 {
            return daysOfWeek.first!
        } else {
            let shortened = Set(daysOfWeek.map{String($0.prefix(3))})
            return Calendar.current.shortWeekdaySymbols.filter{shortened.contains($0)}.joined(separator: ",")
        }
        //TODO store ints instead of names, and use the other swift array
    }
    
    func copyConfigFrom(_ alarm: AlarmModel) {
        selectedSound = alarm.selectedSound
        duration = alarm.duration
        repetitions = alarm.repetitions
        repetitionDelay = alarm.repetitionDelay
        isExtra = alarm.isExtra
    }
    
    func isRecurring() -> Bool {
        return alarmType == .weekDay || alarmType == .saturday || alarmType == .roshChodesh
    }
}

enum AlarmType: Int, Codable, Comparable {
    case explicit = 0
    case yomTov = 10
    case specialSaturday = 18
    case saturday = 20
    case national = 30
    case minor = 40
    case fast = 50
    case cholHamoed = 60
    case roshChodesh = 70
    case weekDay = 80

    static func ==(lhs: AlarmType, rhs: AlarmType) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    static func <(lhs: AlarmType, rhs: AlarmType) -> Bool {
       return lhs.rawValue < rhs.rawValue
    }
}
