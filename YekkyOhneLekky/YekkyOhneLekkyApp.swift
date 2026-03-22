import SwiftUI
import SwiftData
import AppIntents
import BackgroundTasks
import AlarmKit
import OSLog

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static var subsystem = Bundle.main.bundleIdentifier!
    
    /// Logs the view cycles like a view that appeared.
    static nonisolated let shared = Logger(subsystem: subsystem, category: "foo")
}

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
        do {
            let configuredAlarms = try container.mainContext.fetch(FetchDescriptor<AlarmModel>()).filter{$0.isEnabled}.map{$0.name+": "+$0.nextDayToFire.description}.joined(separator: ", ")
            Logger.shared.info("Configured alarms: \(configuredAlarms)")
        } catch {
            Logger.shared.error("Could not fetch all alarms")
        }
    }
    
    
    
    nonisolated func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60) //if the phone is entirely off when an alarm was supposed to ring, perhaps this will handle it, assuming the phone is turned on at least six hours before the next alarm in that categorys should ring
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.shared.notice("Could not schedule app refresh: \(error)")
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
            if AlarmActor.shared == nil {
                Logger.shared.info("AlarmActor.shared is nil!")
            } else {
                try await AlarmActor.shared.scheduleNextAlarms()
            }
        } catch {
            Logger.shared.info("Error scheduling next alarms")
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

enum AlarmError: Error, Sendable {
    case permissionDenied
    case ugh
}

