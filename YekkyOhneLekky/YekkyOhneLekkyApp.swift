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
    let alarmActor: AlarmActor
    
    init() {
        do {
            container = try ModelContainer(for: AlarmModel.self, AlarmLogger.AlarmLog.self)
        } catch {
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = applicationSupportURL.appending(path: "default.store")
            
            do {
//                try FileManager.default.copyItem(at: storeURL, to: storeURL.appending(path: "bak")) //reason=Can't find or automatically infer mapping model for migration, NSUnderlyingError=0x600000ca9380 {Error Domain=NSCocoaErrorDomain Code=134190 "(null)" UserInfo={entity=AlarmModel, property=nextDayToFire, reason=Source and destination attribute types are incompatible}}
                try FileManager.default.removeItem(at: storeURL)
                //sqlite keeps uncommitted pages beside the store; left behind, they can stop the new store from opening
                try? FileManager.default.removeItem(at: URL(filePath: storeURL.path() + "-wal"))
                try? FileManager.default.removeItem(at: URL(filePath: storeURL.path() + "-shm"))
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
    
    var body: some Scene {
        WindowGroup {
            ContentView(showAlert: $showAlert)
                .task(id: phase) {
//                    AlarmLogger.shared.info("foreground task")
                    guard phase == .active else { return }
                    while !Task.isCancelled {
                        do {
                            try await alarmActor.scheduleNextAlarms()
                        } catch {
                            AlarmLogger.shared.error("scheduleNextAlarms failed: \(String(describing: error))")
                        }
                        try? await Task.sleep(for: BackgroundRefresh.interval)
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: phase) { _, newPhase in
            if newPhase == .background {
                BackgroundRefresh.submit()
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.submit() //request the next run first, so the chain continues even if iOS cuts this one short
            AlarmLogger.shared.info("running background task")
            do {
                try await alarmActor.scheduleNextAlarms()
            } catch {
                AlarmLogger.shared.error("scheduleNextAlarms failed: \(String(describing: error))")
            }
        }
    }
}

enum BackgroundRefresh {
    nonisolated static let identifier = "YekkyOhneLekky.refresh"
    nonisolated static let interval = Duration.seconds(3 * 60 * 60)
    
    nonisolated static func submit() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval  / .seconds(1))
        do {
            try BGTaskScheduler.shared.submit(request)
            BGTaskScheduler.shared.getPendingTaskRequests { pending in
                AlarmLogger.shared.info("bg pending: " + pending.map { "\($0.identifier) after \($0.earliestBeginDate?.formatted(date: .omitted, time: .shortened) ?? "?")" }.joined(separator: ", "))
            }
        } catch {
            AlarmLogger.shared.error("Could not submit bg task request: \(String(describing: error))")
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
