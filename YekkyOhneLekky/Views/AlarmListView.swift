import SwiftUI
import SwiftData
import Hebcal
import AlarmKit

struct AlarmListView: View {
    @Binding var showModal: Bool
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
                HStack {
                    Spacer()
                    Button("Disable all") {
                    }.onTapGesture {
                        for alarm in alarms {
                            alarm.isEnabled = false
                            alarm.unschedule()
                        }
                    }.sensoryFeedback(.warning, trigger: alarms)
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
                for alarm in alarms {
                    if alarm.isEnabled && alarm.alarmType == .explicit {
                        modelContext.delete(alarm)
                    }
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
