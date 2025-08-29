import Foundation
internal import SwiftData
internal import SwiftUI

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
    
    init(id: UUID = UUID(), name: String, hour: Int, minute: Int, nextDayToFire: Date?, isActive: Bool = true, selectedSound: String? = nil) {
        self.id = id
        self.name = name
        self.hour = hour
        self.minute = minute
        self.nextDayToFire = nextDayToFire
        self.isActive = isActive
        self.createdAt = Date()
        self.selectedSound = selectedSound
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
}

