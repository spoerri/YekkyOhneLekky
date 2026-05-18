import SwiftData
import AVFoundation
import AlarmKit
import OSLog

@ModelActor
actor AlarmActor {
    static let shared: AlarmActor = {
        //AlarmLogger.shared.info("initializing AlarmActor")
        let container = try! ModelContainer(for: AlarmModel.self)
        return AlarmActor(modelContainer: container)
    }()
    
    func scheduleNextAlarms() async throws {
        //AlarmLogger.shared.info("Rescheduling")
        AlarmLogic.printScheduledAlarms()
        let today = await Testable.Date()
        try await AlarmLogic.disablePastOneOffs(today, modelContext) //to avoid previous alarm today from overriding
        for alarm in try ModelContext(modelContainer).fetch(FetchDescriptor<AlarmModel>()) {
            try await AlarmLogic.reschedule(today, alarm)
        }
        try modelContext.save()
        AlarmLogic.printScheduledAlarms()
    }
}
