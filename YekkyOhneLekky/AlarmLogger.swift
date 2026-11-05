import Foundation
import OSLog
import SwiftData

public class AlarmLogger {
    public nonisolated static let shared: AlarmLogger = .init()
    //the main context, so LogView's @Query sees new entries live. Only ever touched on the main thread: it isn't thread safe, and writing to it from the background task raced with its autosave and saved some logs twice
    @MainActor var modelContext: ModelContext?

    @Model
    public class AlarmLog {
        public var date: Date
        public var composedMessage: String
//        public var level: OSLogType
        
        public init(composedMessage: String, level: OSLogType, date: Date = Date()) {
            self.date = date
            self.composedMessage = composedMessage
//            self.level = level
        }
    }
    
    public nonisolated init() {}
    
    public nonisolated func error(_ message: String) {
        write(message, level: .error, prune: false)
//        Logger.shared.error("\(message, privacy: .public)")
    }
    
    public nonisolated func info(_ message: String) {
        write(message, level: .info, prune: true)
//        Logger.shared.info("\(message, privacy: .public)")
    }
    
    //callable from any thread. Waits for the main thread rather than handing the write off, so a log made just before a background task finishes isn't lost when iOS suspends the app
    private nonisolated func write(_ message: String, level: OSLogType, prune: Bool) {
        let date = Date() //when it was logged, not when the main thread got to it
        if Thread.isMainThread {
            MainActor.assumeIsolated { save(message, level: level, date: date, prune: prune) }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { save(message, level: level, date: date, prune: prune) }
            }
        }
    }
    
    @MainActor private func save(_ message: String, level: OSLogType, date: Date, prune: Bool) {
        guard let context = modelContext else { return }
        do {
            context.insert(AlarmLog(composedMessage: message, level: level, date: date))
            try context.save()
        } catch {
            print("Failed to save log")
        }
        guard prune else { return }
        do {
            if let discardDate = Calendar.current.date(byAdding: .day, value: -7, to: date) {
                let predicate = #Predicate<AlarmLog> { $0.date < discardDate }
                let count = try context.fetchCount(FetchDescriptor(predicate: predicate))
                if count > 0 {
                    try context.delete(model: AlarmLog.self, where: predicate)
                    context.insert(AlarmLog(composedMessage: "deleted \(count) logs older than \(discardDate.formatted())", level: .info))
                    try context.save()
                }
            }
        } catch {
            print("Failed to prune logs")
        }
    }
}
