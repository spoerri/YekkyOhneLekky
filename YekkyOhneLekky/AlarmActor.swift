import SwiftData
import AVFoundation
import AlarmKit
import OSLog

@ModelActor
actor AlarmActor {
    private var isRunning = false
    
    //Called from the foreground timer, the background refresh and the alarms' stop intent, which can overlap.
    //The actor alone doesn't stop that, since it's reentrant at every await.
    func scheduleNextAlarms() async throws {
        if isRunning {
            AlarmLogger.shared.info("already running")
            return
        }
        isRunning = true
        defer { isRunning = false }
        
        let today = await Testable.Date()
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>()) { //same context as below, so scheduleNext sees these changes and they get saved
            try await AlarmLogic.reschedule(today, modelContext, alarm)
        }
        await AlarmLogic.scheduleNext(today, modelContext)
        try modelContext.save()
    }
}
