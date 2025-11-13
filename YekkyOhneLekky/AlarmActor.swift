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
        print("Rescheduling")
        for alarm in try ModelContext(modelContainer).fetch(FetchDescriptor<AlarmModel>()) {
            await AlarmLogic.schedule(alarm)
        }
        //only delete expired alarms _after_ we schedule next alarms, because today's alarm could've been overridden by an expired
        for alarm in try ModelContext(modelContainer).fetch(FetchDescriptor<AlarmModel>()) {
            if alarm.isExplicit && alarm.name != AlarmLogic.Once && alarm.nextDayToFire < Date() {
                print("one off alarm expired")
                alarm.isEnabled = false
//                modelContext.delete(alarm) //TODO why doesn't this work?
            }
        }
        try modelContext.save()
    }
}
