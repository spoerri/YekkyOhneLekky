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
    var nextDayToFire: Date? //could be nil because there's an explicit alarm for that date this year
    var isEnabled: Bool
    var isGrouped: Bool
    var daysOfWeek: Set<String>
    var selectedSound: String?
    var createdAt: Date
    var duration: TimeInterval
    var repetitions: Int
    var repetitionDelay: TimeInterval
    var alarmType: Int //sad, maybe one day we'll be able to use the enum type here
    
    init(name: String, ids: Array<UUID> = Array(), hour: Int, minute: Int, nextDayToFire: Date?, isEnabled: Bool = true, isGrouped: Bool = true, daysOfWeek: Set<String> = Set(), selectedSound: String? = nil, duration: TimeInterval = 60, repetitions: Int = 1, repetitionDelay: TimeInterval = 240) {
        self.name = name
        self.ids = ids
        self.hour = hour
        self.minute = minute
        self.nextDayToFire = nextDayToFire
        self.isEnabled = isEnabled
        self.isGrouped = isGrouped
        self.daysOfWeek = daysOfWeek
        self.createdAt = Date()
        self.selectedSound = selectedSound
        self.duration = duration
        self.repetitions = repetitions
        self.repetitionDelay = repetitionDelay
        self.alarmType = (AlarmLogic.allDaysOfWeek.contains(name) ? AlarmType.dayOfWeek : AlarmType.yomtov).rawValue
    }
    
    var timeString: String {
        return String(format: "%02d", hour)+":"+String(format: "%02d", minute)
//        let formatter = DateFormatter()
//        formatter.timeStyle = .short
//        let date = getAlarmDate() ?? Date()
//        return formatter.string(from: date)
    }
    
    func getAlarmDate() -> Date? {
        if let n = nextDayToFire {
            return Calendar.current.date(bySettingHour: hour, minute: minute, second:0, of: n, matchingPolicy: .nextTime)
        } else {
            return nil
        }
    }
    
    static let dayOfWeek = AlarmType.dayOfWeek.rawValue
    static let explicit = AlarmType.explicit.rawValue
    static let yomtov = AlarmType.yomtov.rawValue
    
    func unschedule() {
        if isEnabled {
            do {
                for id in ids {
                    try AlarmManager.shared.stop(id: id)
                }
            } catch {
                print("could not cancel \(id)")
            }
        }
    }
}

enum AlarmType: Int, Codable, Comparable {
    case explicit = 0
    case yomtov = 1 //shabbos should be treated as chag for most things
    case minor = 2
    case legal = 3
    case roshchodesh = 4
    case dayOfWeek = 5

     static func ==(lhs: AlarmType, rhs: AlarmType) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    static func <(lhs: AlarmType, rhs: AlarmType) -> Bool {
       return lhs.rawValue < rhs.rawValue
    }
}
