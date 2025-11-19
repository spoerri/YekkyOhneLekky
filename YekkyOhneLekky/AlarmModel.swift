import Foundation
import SwiftData
import SwiftUI
import AVFoundation
import AlarmKit

@Model
class AlarmModel {
    @Attribute(.unique) var name: String
    var ids: Array<UUID>
    var hour: Int
    var minute: Int
    var nextDayToFire: Date
    var isEnabled: Bool
    var isOverridden: Bool
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
    
    init(name: String, alarmType: AlarmType, ids: Array<UUID> = Array(), hour: Int, minute: Int, nextDayToFire: Date, isEnabled: Bool = true, isOverridden: Bool = false, isGrouped: Bool = false, daysOfWeek: Set<String> = Set(), selectedSound: String? = nil, duration: TimeInterval = 60, repetitions: Int = 1, repetitionDelay: TimeInterval = 240) {
        self.name = name
        self.ids = ids
        self.hour = hour
        self.minute = minute
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
    }
    
    var timeString: String {
//        if let earliest = getEarliestTimeIfEarlier() {
//            return String(format: "%02d", earliest[0])+":"+String(format: "%02d", earliest[1])
//        }
        return String(format: "%02d", hour)+":"+String(format: "%02d", minute)
    }
    
    private func getEarliestTimeIfEarlier() -> [Int]? {
        if let earliest = AlarmLogic.getEarliest(nextDayToFire) {
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
    
    func getAlarmDate() throws -> Date {
//        if let earliest = getEarliestTimeIfEarlier() {
//            return try getAlarmDate(nextDayToFire, earliest[0], earliest[1])
//        }
        return try getAlarmDate(nextDayToFire)
    }
    
    func getAlarmDate(_ arbitraryDay: Date, _ h: Int? = nil, _ m: Int? = nil) throws -> Date {
        guard let fullDate = Calendar.current.date(bySettingHour: h ?? hour, minute: m ?? minute, second:0, of: arbitraryDay, matchingPolicy: .nextTime) else { throw AlarmError.ugh }
        return fullDate
    }
    
    func unschedule() {
        if isEnabled {
            do {
                for id in ids {
                    if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
                        print("Unscheduling", id)
                        try AlarmManager.shared.stop(id: id)
                    }
                }
            } catch {
                print("could not cancel \(id)")
            }
        }
    }
    
    func setNameFromDaysOfWeek() {
        if daysOfWeek.count == 6 {
            name = "Sun-Fri" //otherwise it's too long
        } else if daysOfWeek.count == 1 {
            name = daysOfWeek.first!
        } else {
            let shortened = Set(daysOfWeek.map{String($0.prefix(3))})
            name = Calendar.current.shortWeekdaySymbols.filter{shortened.contains($0)}.joined(separator: ",")
        }
        //TODO store ints instead of names, and use the other swift array
    }
}

enum AlarmType: Int, Codable, Comparable {
    case explicit = 0
    case yomTov = 1
    case saturday = 2
    case national = 3
    case minor = 5
    case fast = 4
    case cholHamoed = 6
    case roshChodesh = 7
    case weekDay = 8
    //TODO future proof it somehow? maybe separate precedence field

     static func ==(lhs: AlarmType, rhs: AlarmType) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    static func <(lhs: AlarmType, rhs: AlarmType) -> Bool {
       return lhs.rawValue < rhs.rawValue
    }
}
