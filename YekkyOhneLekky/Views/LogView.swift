import Foundation
import OSLog
import SwiftUI
import UIKit
import SwiftData

struct LogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
        HStack {
            Spacer()
            Button("Delete All Data") {
                modelContext.container.deleteAllData()
            }
            Spacer()
            Button("Dismiss") {
                dismiss()
            }
            Spacer()
            Button("Copy") {
                UIPasteboard.general.string = logs.map { $0.composedMessage }.joined(separator: "\n")
            }
            Spacer()
        }
    }
}
