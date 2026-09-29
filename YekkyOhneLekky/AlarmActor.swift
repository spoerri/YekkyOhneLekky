import SwiftData
import AVFoundation
import AlarmKit
import OSLog

@ModelActor
actor AlarmActor {
    func scheduleNextAlarms() async throws {
        await AlarmLogic.printScheduledAlarms()
        let today = await Testable.Date()
        try await AlarmLogic.disablePastOneOffs(today, modelContext) //at some point needed here, to avoid previous alarm today from overriding
        for alarm in try ModelContext(modelContainer).fetch(FetchDescriptor<AlarmModel>()) {
            try await AlarmLogic.reschedule(today, modelContext, alarm)
        }
        try modelContext.save()
        await AlarmLogic.printScheduledAlarms()
    }
}
