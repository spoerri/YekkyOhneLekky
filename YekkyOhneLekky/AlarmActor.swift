import SwiftData
import AVFoundation
import AlarmKit

@ModelActor
actor AlarmActor {
    private(set) static var shared: AlarmActor!
    
    static func createSharedInstance(modelContext: ModelContext) {
        shared = AlarmActor(modelContainer: modelContext.container)
    }
    
    func scheduleNextAlarms() async throws {
        for alarm in try ModelContext(modelContainer).fetch(FetchDescriptor<AlarmModel>()) {
//                print("Considering alarm to reschedule " + alarm.name)
            guard let alarmDate = alarm.getAlarmDate() else {
                print("Failed to figure alarm time for \(alarm.name)");
                continue
            }
            if (alarmDate < Date()) {
                alarm.nextDayToFire = await AlarmLogic.getDate(nameOfAlarm: alarm.name)
                await AlarmLogic.scheduleAlarm(alarm: alarm)
            } else if await (try !AlarmLogic.isScheduled(alarm)) {
                await AlarmLogic.scheduleAlarm(alarm: alarm)
            }
        }
    }
}
