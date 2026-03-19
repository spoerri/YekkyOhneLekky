import SwiftData
import AVFoundation
import AlarmKit
import OSLog

@ModelActor
actor AlarmActor {
    static let shared: AlarmActor = {
        Logger.shared.info("initializing AlarmActor")
        let container = try! ModelContainer(for: AlarmModel.self)
        return AlarmActor(modelContainer: container)
    }()
    
    func scheduleNextAlarms() async throws {
        Logger.shared.info("Rescheduling")
        AlarmLogic.printScheduledAlarms()
        for alarm in try ModelContext(modelContainer).fetch(FetchDescriptor<AlarmModel>()) {
            try await AlarmLogic.reschedule(Testable.Date(), alarm)
        }
        try modelContext.save()
        AlarmLogic.printScheduledAlarms()
    }
}
