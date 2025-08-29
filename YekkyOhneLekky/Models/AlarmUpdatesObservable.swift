import AlarmKit
import SwiftData

@Observable class AlarmUpdatesObservable {
    @ObservationIgnored private let alarmManager = AlarmManager.shared
    
    static let shared = AlarmUpdatesObservable()
    
    var modelContext: ModelContext?

    init() {
        Task {
            for await incomingAlarms in alarmManager.alarmUpdates {
                Task { @MainActor in
                    if (modelContext != nil) {
                        let configuredAlarms = try modelContext!.fetch(FetchDescriptor<AlarmModel>())
                        var firedAlarms: [AlarmModel] = []
                        for configuredAlarm in configuredAlarms {
                            if !incomingAlarms.contains(where: { $0.id == configuredAlarm.id }) {
                                firedAlarms.append(configuredAlarm)
                            }
                        }
                        if (firedAlarms.count > 0) {
                            await EditAlarmView.scheduleNext(modelContext: modelContext!, alarms: firedAlarms)
                        }
                    }
                }
            }
        }
    }
}
