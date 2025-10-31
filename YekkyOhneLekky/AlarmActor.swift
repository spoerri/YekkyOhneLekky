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
        //TODO split the sorting away from AlarmListView and instead share with EditAlarmView.initializeAlarms to ensure holiday alarm beats weekDay alarm, especially because with nicer UI, week day alarms will want to be sorted to the top in AlarmListView
        for alarm in try ModelContext(modelContainer).fetch(FetchDescriptor<AlarmModel>(sortBy: AlarmListView.alarmOrder)) {
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
