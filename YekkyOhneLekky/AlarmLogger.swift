import OSLog

public class AlarmLogger {
    public static let shared: AlarmLogger = .init()
    
    public func error(_ message: String) {
        Logger.shared.error("\(message)")
    }
    
    public func info(_ message: String) {
        Logger.shared.info("\(message)")
    }
}

