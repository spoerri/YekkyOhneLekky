import SwiftUI
import SwiftData
import Hebcal
import AlarmKit
import OSLog

struct AlarmListView: View {
    @Binding var showModal: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var alarms: [AlarmModel]
    @State private var editingAlarm: AlarmModel?
    @State private var showAlert = false

    private var sortedAlarms: [AlarmModel] {
        alarms.sorted { adjusted($0) < adjusted($1) }
    }

    private func adjusted(_ a: AlarmModel) -> Double {
        do {
            var d: Date = try a.getAlarmDateAndTime()
            if a.name == AlarmLogic.Once {
                return 0
            }
            if d < Testable.Date() { //for things that don't come every year, e.g. sometimes vayakehl&Pekudei are not a double parsha
                d = Calendar.current.date(byAdding: .year, value: 2, to: d)!
            }
            return d.timeIntervalSince1970
        } catch {
            AlarmLogger.shared.error("Couldn't getAlarmDateAndTime")
            return 0
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedAlarms) { alarm in
                    AlarmRowView(alarm: alarm)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            editingAlarm = alarm
                        }
                }
                HStack {
                    Spacer()
                    Button("Disable all") {
                    }.onTapGesture {
                        for alarm in alarms {
                            alarm.isEnabled = false
                            do {
                                try alarm.unschedule()
                            } catch {
                                AlarmLogger.shared.error("Couldn't disable all")
                                showAlert = true
                            }
                        }
                    }.sensoryFeedback(.warning, trigger: alarms)
                    .foregroundColor(.red)
                    .frame(width: 180, alignment: .leading)
                    .padding()
                    Button("About") {
                    }.onTapGesture {
                        showModal.toggle()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            .sheet(item: $editingAlarm) { alarm in
                EditAlarmView(editingAlarm: alarm)
            }
            .task {
                do {
                    try await AlarmLogic.initializeAlarms(Testable.Date(), modelContext: modelContext, alarms: alarms)
                } catch {
                    AlarmLogger.shared.error("Could not initialize")
                    showAlert = true
                }
            }
        }
        .alert("Encountered a problem", isPresented: $showAlert) {
        } message: {
            Text("Try again, or try something similar")
        }
    }
}

struct AlarmRowView: View {
    let alarm: AlarmModel
    
    var body: some View {
        VStack() {
            HStack {
                Text(alarm.name)
                    .font(.headline)
                    .frame(width: 180, alignment: .leading)
                    .padding()
                
                Text(alarm.isEnabled ? alarm.timeString : "")
                    .strikethrough(alarm.isOverridden)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    @Previewable @State var value = false
    AlarmListView(showModal: $value)
        .modelContainer(for: AlarmModel.self, inMemory: true)
}
