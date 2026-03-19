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
    var maybeDayToFire: Date //note that this may or may not have the alarm time in it
    var nextDayToFire: Date //note that this may or may not have the alarm time in it
    var isEnabled: Bool
    var isOverridden: Bool //TODO this is probably not correct
    var isGrouped: Bool
    var daysOfWeek: Set<String>
    var selectedSound: String?
    var createdAt: Date
    var duration: TimeInterval?
    var repetitions: Int
    var repetitionDelay: TimeInterval
    var alarmType: AlarmType
    var isExplicit: Bool
    var isWeekDay: Bool
    var isShabbos: Bool
    
    init(name: String, alarmType: AlarmType, ids: Array<UUID> = Array(), daysOfWeek: Set<String> = Set(), hour: Int, minute: Int, maybeDayToFire: Date, nextDayToFire: Date, isEnabled: Bool = true, isOverridden: Bool = false, isGrouped: Bool = false, selectedSound: String? = nil, duration: TimeInterval = 60, repetitions: Int = 1, repetitionDelay: TimeInterval = 240) {
        self.name = name
        self.ids = ids
        self.hour = hour
        self.minute = minute
        self.maybeDayToFire = maybeDayToFire
        self.nextDayToFire = nextDayToFire
        self.isEnabled = isEnabled
        self.isOverridden = isOverridden
        self.isGrouped = isGrouped
        self.daysOfWeek = daysOfWeek
        self.createdAt = Date()
        self.selectedSound = selectedSound
        self.duration = duration
        self.repetitions = repetitions
        self.repetitionDelay = repetitionDelay
        self.alarmType = alarmType
        
        self.isExplicit = alarmType == .explicit
        self.isWeekDay = alarmType == .weekDay
        self.isShabbos = alarmType == .saturday
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
    
    func getAlarmDateAndTime(_ date: Date, _ h: Int? = nil, _ m: Int? = nil) throws -> Date {
        guard let fullDate = Calendar.current.date(bySettingHour: h ?? hour, minute: m ?? minute, second:0, of: nextDayToFire) else { throw AlarmError.ugh }
        return fullDate
    }
    
    func unschedule() throws {
        for id in ids {
            if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
                Logger.shared.notice("Unscheduling \(id, privacy: .public)")
                do {
                    try AlarmManager.shared.stop(id: id)
                } catch {
                    Logger.shared.info("could not cancel \(id)")
                }
            }
        }
        ids.removeAll()
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
