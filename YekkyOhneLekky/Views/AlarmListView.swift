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
        alarms.sorted { (adjusted($0), $0.name) < (adjusted($1), $1.name) }
    }

    //the day to sort by
    private func adjusted(_ a: AlarmModel) -> String {
        if a.name == AlarmLogic.Once {
            return ""
        }
        let today = AlarmModel.day(Testable.Date())
        var day = a.nextDayToFire
        if day < today { //for disabled and things that don't come every year, e.g. sometimes vayakehl&Pekudei are not a double parsha
            if a.alarmType == .roshChodesh {
                day = AlarmModel.addingDays(today, 7) //after week days
            } else if !a.isRecurring() {
                day = AlarmModel.addingYears(day, 2)
            }
        }
        return day
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
                let now = Testable.Date()
                do {
                    try await AlarmLogic.initializeAlarms(now, modelContext)
                } catch {
                    AlarmLogger.shared.error("Failed to initialize: \(error)")
                    showAlert = true
                }
                for alarm in alarms.filter({$0.nextDayToFire < AlarmModel.day(now) && $0.alarmType == .explicit && $0.name != AlarmLogic.Once}) {
                    modelContext.delete(alarm)
                }
                await AlarmLogic.scheduleNext(now, modelContext)
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
