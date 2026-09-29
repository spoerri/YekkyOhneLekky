import SwiftData
import AVFoundation
import AlarmKit
import OSLog

@ModelActor
actor AlarmActor {
    private var isRunning = false
    private var runAgain = false
    
    //Called from the foreground timer, the background refresh and the alarms' stop intent, which can overlap.
    //The actor alone doesn't stop that, since it's reentrant at every await.
    func scheduleNextAlarms() async throws {
        if isRunning {
            return
        }
        isRunning = true
        defer { isRunning = false }
        
        try await scheduleNextAlarmsOnce()
        //await AlarmLogic.printScheduledAlarms()
    }
    
    private func scheduleNextAlarmsOnce() async throws {
        let today = await Testable.Date()
        try await AlarmLogic.disablePastOneOffs(today, modelContext) //at some point needed here, to avoid previous alarm today from overriding
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>()) { //same context as below, so scheduleNext sees these changes and they get saved
            try await AlarmLogic.reschedule(today, modelContext, alarm)
        }
        await AlarmLogic.scheduleNext(today, modelContext)
        try modelContext.save()
    }
}
