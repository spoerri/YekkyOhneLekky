import SwiftUI
import SwiftData
import Hebcal
import AlarmKit

struct AlarmListView: View {
    @Binding var showModal: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AlarmModel.alarmType), SortDescriptor(\AlarmModel.nextDayToFire)]) private var alarms: [AlarmModel]
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
                HStack {
                    Spacer()
                    Button("Disable all") {
                    }.onTapGesture {
                        for alarm in alarms {
                            alarm.isEnabled = false
                            alarm.unschedule()
                        }
                    }
                    .foregroundColor(.red)
                    .frame(width: 180, alignment: .leading)
                    .padding()
                    Button("About") { //TODO is it just me, or is this higher?
                    }.onTapGesture {
                        showModal.toggle()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            .onAppear {
                AlarmActor.createSharedInstance(modelContext: modelContext)
            }
            .sheet(item: $editingAlarm) { alarm in
                EditAlarmView(editingAlarm: alarm)
            }
            .task {
                let explicit: Int = AlarmModel.explicit
                do {
                    try modelContext.delete(model: AlarmModel.self, where: #Predicate { $0.alarmType == explicit && !$0.isEnabled }) //TODO error: forcedunwrap?
                } catch {
                    print("couldn't delete old one off alarms: \(error)")
                }
                await AlarmLogic.initializeAlarms(modelContext: modelContext, alarms: alarms)
            }
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
