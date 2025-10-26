import Foundation
import SwiftData
import SwiftUI
import AVFoundation

@Model
class AlarmModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var hour: Int
    var minute: Int
    var nextDayToFire: Date?
    var isActive: Bool
    var createdAt: Date
    var selectedSound: String?
    var alarmType: Int? //TODO what's wrong with persisting my enum? breaks the @Query sort in AlarmListView
    
    init(id: UUID = UUID(), name: String, hour: Int, minute: Int, nextDayToFire: Date?, isActive: Bool = true, selectedSound: String? = nil) {
        self.id = id
        self.name = name
        self.hour = hour
        self.minute = minute
        self.nextDayToFire = nextDayToFire
        self.isActive = isActive
        self.createdAt = Date()
        self.selectedSound = selectedSound
        self.alarmType = AlarmLogic.weekDays.contains(name) ? AlarmType.dayOfWeek.rawValue : AlarmType.holiday.rawValue
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let date = getAlarmDate() ?? Date()
        return formatter.string(from: date)
    }
    
    func getAlarmDate() -> Date? {
        return Calendar.current.date(bySettingHour: hour, minute: minute, second:0, of: nextDayToFire!, matchingPolicy: .nextTime)
    }
}

enum AlarmType: Int, Codable, Comparable {
    case holiday = 0
    case dayOfWeek = 1

     static func ==(lhs: AlarmType, rhs: AlarmType) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    static func <(lhs: AlarmType, rhs: AlarmType) -> Bool {
       return lhs.rawValue < rhs.rawValue
    }
}
