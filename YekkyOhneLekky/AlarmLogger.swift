import OSLog
import SwiftData

public class AlarmLogger {
    public nonisolated static let shared: AlarmLogger = .init()
    //TODO fix this nonsense
    nonisolated(unsafe) var modelContext: ModelContext?

    @Model
    public class AlarmLog {
        public var date: Date
        public var composedMessage: String
//        public var level: OSLogType
        
        public init(composedMessage: String, level: OSLogType) {
            self.date = Date()
            self.composedMessage = composedMessage
//            self.level = level
        }
    }
    
    public init() {}
    
    public nonisolated func error(_ message: String) {
        guard let context = modelContext else { return }
        context.insert(AlarmLog(composedMessage: message, level: .error))
        do {
            try context.save()
        } catch {
            print("Failed to save log")
        }
//        Logger.shared.error("\(message, privacy: .public)")
    }
    
    public nonisolated func info(_ message: String) {
        guard let context = modelContext else { return }
        do {
            context.insert(AlarmLog(composedMessage: message, level: .info))
            try context.save()
        } catch {
            print("Failed to save log")
        }
        do {
            if let discardDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
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
//        Logger.shared.info("\(message, privacy: .public)")
    }
}

