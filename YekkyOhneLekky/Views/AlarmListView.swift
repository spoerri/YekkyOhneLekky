internal import SwiftUI
internal import SwiftData
import Hebcal

struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlarmModel.nextDayToFire) private var alarms: [AlarmModel]
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
            }
            .sheet(item: $editingAlarm) { alarm in
                EditAlarmView(editingAlarm: alarm)
            }
            .task {
//                do {
//                    try modelContext.delete(model: AlarmModel.self)
//                } catch {
//                    print("Failed to delete all instances of YourModelName: \(error.localizedDescription)")
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
                
                //TODO show the date of next firing here too?
                
                Text(alarm.timeString)
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
