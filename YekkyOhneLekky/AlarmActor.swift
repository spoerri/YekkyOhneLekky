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
        
        do {
            try await AlarmLogic.unscheduleAllIfTimeZoneChanged(modelContext)
        } catch {
            AlarmLogger.shared.error("Couldn't unschedule after a time zone change: \(error)")
        }
        let today = await Testable.Date()
        try await AlarmLogic.rescheduleAll(today, modelContext) //same context as below, so scheduleNext sees these changes and they get saved
        await AlarmLogic.scheduleNext(today, modelContext)
        try modelContext.save()
    }
    
    func dismissAlarm(withID id: UUID) async throws {
        while isRunning {
            try await Task.sleep(for: .milliseconds(100))
        }
        isRunning = true
        defer { isRunning = false }
        
        let today = await Testable.Date()
        try await AlarmLogic.dismissAlarm(withID: id, today, modelContext)
    }
}
