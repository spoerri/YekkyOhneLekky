import Foundation
import OSLog
import SwiftUI

struct LogView: View {
    @Environment(\.dismiss) private var dismiss
    let logs: [OSLogEntryLog]

    init() {
        let logStore = try! OSLogStore(scope: .currentProcessIdentifier)
        self.logs = try! logStore.getEntries().compactMap { entry in
            guard let logEntry = entry as? OSLogEntryLog,
                  logEntry.subsystem.contains("YekkyOhneLekky") else {
                return nil
            }

            return logEntry
        }
    }

    var body: some View {
        List(logs, id: \.self) { log in
            VStack(alignment: .leading) {
                Text(log.composedMessage)
                HStack {
                    Text(log.subsystem)
                    Text(log.date, format: .dateTime)
                }.bold()
            }
        }
        Button("Dismiss") {
            dismiss()
        }
    }
}
