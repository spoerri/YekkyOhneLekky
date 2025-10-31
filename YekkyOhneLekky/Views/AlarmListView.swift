import SwiftUI
import SwiftData
import Hebcal
import AlarmKit

struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    static nonisolated let alarmOrder = [SortDescriptor(\AlarmModel.alarmType), SortDescriptor(\AlarmModel.nextDayToFire)]
    @Query(sort: alarmOrder) private var alarms: [AlarmModel]
    @State private var editingAlarm: AlarmModel?
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(alarms) { alarm in
                    AlarmRowView(alarm: alarm)
                        .onTapGesture {
                            editingAlarm = alarm
                        }
                }
            }
            .onAppear {
                for alarm in alarms {
                    print("  - \(alarm.name) at \(alarm.timeString)")
                }
                AlarmActor.createSharedInstance(modelContext: modelContext)
            }
            .sheet(item: $editingAlarm) { alarm in
                EditAlarmView(editingAlarm: alarm)
            }
            .task {
                //only used for dev, to clear out entries that were never created in a real release
                do {
                    try modelContext.delete(model: AlarmModel.self)
                } catch {
                    print("Failed to delete all instances of YourModelName: \(error.localizedDescription)")
                }
                
                //not sure exactly when this next is useful...
//                do {
//                    for alarm in try AlarmManager.shared.alarms {
//                        try AlarmManager.shared.cancel(id: alarm.id)
//                    }
//                } catch {
//                    print("Could not cancel all alarms")
//                }
                
                await EditAlarmView.initializeAlarms(modelContext: modelContext, alarms: alarms)
            }
        }
    }
}

struct AlarmRowView: View {
    let alarm: AlarmModel
    
    var body: some View {
        VStack(/*alignment: .leading, spacing: 6*/) { //TODO is there some extra spacing at the top?
            
            HStack {
                Text(alarm.name)
                    .font(.headline)
                    .frame(width: 180, alignment: .leading)
                    .padding()
                
                Text(alarm.isActive ? alarm.timeString : "")
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
    AlarmListView()
        .modelContainer(for: AlarmModel.self, inMemory: true)
}

//TODO an "About" view
