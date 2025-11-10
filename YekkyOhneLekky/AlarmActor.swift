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
            if alarm.isExplicit {
//                    alarm.isEnabled = false
                modelContext.delete(alarm)
                continue
            }
            await AlarmLogic.schedule(alarm)
        }
        try modelContext.save()
    }
}
