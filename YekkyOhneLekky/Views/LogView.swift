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
        self.logs = try! logStore.getEntries(
            at: logStore.position(timeIntervalSinceEnd: 7*24*60*60),
            matching: NSPredicate(format: "subsystem = \"\(Logger.subsystem)\"")
        ).compactMap({ $0 as? OSLogEntryLog })
    }

    var body: some View {
        List(logs, id: \.self) { log in
            VStack(alignment: .leading) {
                Text(log.date, format: .dateTime).bold()
                Text(log.composedMessage)
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
