import SwiftData
import AVFoundation
import AlarmKit
import OSLog

@ModelActor
actor AlarmActor {
    private(set) static var shared: AlarmActor!
    
    static func createSharedInstance(modelContext: ModelContext) {
        shared = AlarmActor(modelContainer: modelContext.container)
    }
    
    func scheduleNextAlarms() async throws {
        Logger.shared.info("Rescheduling")
        AlarmLogic.printScheduledAlarms()
        for alarm in try ModelContext(modelContainer).fetch(FetchDescriptor<AlarmModel>()) {
            try await AlarmLogic.reschedule(Date(), alarm)
        }
        try modelContext.save()
        AlarmLogic.printScheduledAlarms()
    }
}
