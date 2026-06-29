import SwiftUI
import SwiftData
import AppIntents
import BackgroundTasks
import AlarmKit
import OSLog

extension Logger {
    static var subsystem = Bundle.main.bundleIdentifier!
    
    static nonisolated let shared = Logger(subsystem: subsystem, category: "MyCategory")
}

@main
struct YekkyOhneLekkyApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var showAlert = false
    let container: ModelContainer
    let bgTaskIdentifier = "YekkyOhneLekky.refresh"
    let alarmActor: AlarmActor
    
    init() {
        do {
            container = try ModelContainer(for: AlarmModel.self, AlarmLogger.AlarmLog.self)
        } catch {
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = applicationSupportURL.appending(path: "default.store")
            
            do {
//                try FileManager.default.copyItem(at: storeURL, to: storeURL.appending(path: "bak")) //TODO figure out why it still fails
                try FileManager.default.removeItem(at: storeURL)
                container = try ModelContainer(for: AlarmModel.self, AlarmLogger.AlarmLog.self)
                AlarmLogger.shared.error("Remove persistence store")
                showAlert = true
            } catch {
                fatalError("Failed to initialize ModelContainer")
            }
        }
        alarmActor = AlarmActor(modelContainer: container)
        AlarmLogger.shared.modelContext = container.mainContext
        let alarmActorCopy = alarmActor
        AppDependencyManager.shared.add { alarmActorCopy }
    }
    
    nonisolated func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60) //if the phone is entirely off when an alarm was supposed to ring, perhaps this will handle it, assuming the phone is turned on at least six hours before the next alarm in that categorys should ring
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AlarmLogger.shared.error("Could not submit bg task request: \(String(describing: error))")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(showAlert: $showAlert)
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
                AlarmLogger.shared.info("backgroundTask")
                try await alarmActor.scheduleNextAlarms()
            } catch {
                AlarmLogger.shared.error("backgroundTask failed: \(String(describing: error))")
            }
        }
    }
}

public struct ScheduleNextAlarmsIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Schedule next YekkyOhneLekky alarm"
    public static var description = IntentDescription("Schedule next YekkyOhneLekky alarm")
    public static var openAppWhenRun = false
    @Dependency private var alarmActor: AlarmActor
    
    public func perform() async throws -> some IntentResult {
        do {
            AlarmLogger.shared.info("intent")
            try await alarmActor.scheduleNextAlarms()
        } catch {
            AlarmLogger.shared.error("intent failed: \(String(describing: error))")
        }
        return .result()
    }

    public init() {
    }
}

enum AlarmError: Error, Sendable {
    case permissionDenied
    case ugh
}
