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
            try await AlarmLogic.reschedule(alarm)
        }
        try modelContext.save()
    }
}
