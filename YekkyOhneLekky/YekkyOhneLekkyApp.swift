import SwiftUI
import SwiftData
import AppIntents
import BackgroundTasks

@main
struct YekkyOhneLekkyApp: App {
    @Environment(\.scenePhase) private var phase
    let container: ModelContainer
    let bgTaskIdentifier = "YekkyOhneLekky.refresh"
    
    init() {
        do {
            container = try ModelContainer(for: AlarmModel.self)
        } catch {
            fatalError("Failed to initialize ModelContainer")
        }
    }
    
    nonisolated func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .onChange(of: phase) { newPhase, arg in //TODO need to care about arg?
            switch newPhase {
                case .background: scheduleAppRefresh()
                default: break
            }
        }
        .backgroundTask(.appRefresh(bgTaskIdentifier)) { @Sendable context in
            do {
                scheduleAppRefresh()
                try await AlarmActor.shared.scheduleNextAlarms()
            } catch {
                
            }
        }
    }
}

public struct ScheduleNextAlarmsIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Schedule next YekkyOhneLekky alarm"
    public static var description = IntentDescription("Schedule next YekkyOhneLekky alarm")
    public static var openAppWhenRun = false
    
    public func perform() async throws -> some IntentResult {
        do {
            try await AlarmActor.shared.scheduleNextAlarms()
        } catch {
            print("Error scheduling next alarms")
        }
        return .result()
    }

    @Parameter(title: "alarmID")
    public var alarmID: String

    public init(alarmID: String) { //alarmID doesn't really matter now, but i believe this is expected signature
        self.alarmID = alarmID
    }

    public init() {
        self.alarmID = ""
    }
}
