import SwiftUI
import SwiftData
import Hebcal
import AlarmKit
import OSLog

struct AlarmListView: View {
    @Binding var showModal: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlarmModel.nextDayToFire) private var alarms: [AlarmModel]
    @State private var editingAlarm: AlarmModel?
    @State private var showAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(alarms) { alarm in
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
                                Logger.shared.info("Couldn't disable all")
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
            .onAppear {
                AlarmActor.createSharedInstance(modelContext: modelContext) //TODO is this the best way?
            }
            .sheet(item: $editingAlarm) { alarm in
                EditAlarmView(editingAlarm: alarm)
            }
            .task {do {
                    try await AlarmLogic.initializeAlarms(Date(), modelContext: modelContext, alarms: alarms)
                } catch {
                    Logger.shared.info("Could not initialize")
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
