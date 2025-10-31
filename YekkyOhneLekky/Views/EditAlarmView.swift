import SwiftUI
import SwiftData
import AlarmKit //TODO move the alarmkit stuff into a separate class
import Foundation
import Hebcal

struct EditAlarmView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let editingAlarm: AlarmModel?
    
    @State private var alarmName = ""
    @State private var alarmType: Int = -1
    @State private var selectedTime = Date()
    @State private var isActive: Bool = true
    @State private var nextDayToFire: String
    @State private var daysOfWeek = Set<String>()
    @State private var showPermissionsDeniedAlert = false
    @State private var selectedSound: String? = nil
    
    init(editingAlarm: AlarmModel? = nil) {
        self.editingAlarm = editingAlarm
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if editingAlarm == nil || editingAlarm!.nextDayToFire == nil {
            self.nextDayToFire = ""
        } else {
            self.nextDayToFire = dateFormatter.string(from:(editingAlarm?.nextDayToFire)!)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                AlarmDetailsView(
                    alarmName: $alarmName,
                    alarmType: $alarmType,
                    selectedTime: $selectedTime,
                    isActive: $isActive,
                    nextDayToFire: $nextDayToFire,
                    daysOfWeek: $daysOfWeek
                )
                SoundSelectionView(selectedSound: $selectedSound)
            }
            .navigationTitle("Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture {
            }
            .onAppear {
                loadAlarmData()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { @MainActor in
                            await saveAlarm()
                        }
                    }
                    .disabled(alarmName.isEmpty)
                }
            }
        }
        .alert("Permissions Required", isPresented: $showPermissionsDeniedAlert) {
            Button("OK") { }
        } message: {
            Text("Please allow alarm permissions in Settings to schedule alarms.")
        }
    }
    
    private func loadAlarmData() {
        guard let alarm = editingAlarm else { return }
        
        alarmName = alarm.name
        alarmType = alarm.alarmType
        selectedSound = alarm.selectedSound
        isActive = alarm.isActive
        daysOfWeek = alarm.daysOfWeek
        
        let calendar = Calendar.current
        if alarmName == AlarmLogic.Once {
            alarm.hour = calendar.component(.hour, from: Date())
            alarm.minute = calendar.component(.minute, from: Date()) + 1
        }
        selectedTime = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? Date()
    }
    
    @MainActor
    private func saveAlarm() async {
        do {
            try await requestAlarmAuthorization()
            
            if let editingAlarm = editingAlarm {
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: selectedTime)
                let minute = calendar.component(.minute, from: selectedTime)
                
                if calendar.standaloneWeekdaySymbols.contains(editingAlarm.name) { //TODO extract a method, or rely on type
                    for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { calendar.standaloneWeekdaySymbols.contains($0.name) })) {
                        if alarm.name == editingAlarm.name {
                            continue
                        }
                        do {
                            try AlarmManager.shared.stop(id: alarm.id)
                        } catch {
                            print("could not cancel \(alarm.id)")
                        }
                        if daysOfWeek.contains(alarm.name) {
                            alarm.hour = hour
                            alarm.minute = minute
                            alarm.isActive = isActive
                            alarm.daysOfWeek = daysOfWeek
                            alarm.selectedSound = selectedSound
                            alarm.nextDayToFire = AlarmLogic.getDate(nameOfAlarm: alarm.name)
                            await AlarmLogic.scheduleAlarm(alarm: alarm)
                        } else {
                            alarm.daysOfWeek.subtract(daysOfWeek)
                        }
                    }
                }
                
                editingAlarm.hour = hour
                editingAlarm.minute = minute
                editingAlarm.isActive = isActive
                editingAlarm.daysOfWeek = daysOfWeek
                editingAlarm.selectedSound = selectedSound
                editingAlarm.nextDayToFire = AlarmLogic.getDate(nameOfAlarm: alarmName)
                
                //TODO any crash scenarios?
                
                do {
                    try AlarmManager.shared.stop(id: editingAlarm.id)
                } catch {
                    print("could not cancel \(editingAlarm.id)")
                }
                
                await AlarmLogic.scheduleAlarm(alarm: editingAlarm)
                
                if editingAlarm.name == AlarmLogic.Once {
                    editingAlarm.isActive = false
                }
                
                try modelContext.save()
            }
            
            dismiss()
        } catch {
            print("Error saving alarm: \(error)")
        }
    }
    
    public static func initializeAlarms(modelContext: ModelContext, alarms: [AlarmModel]) async {
        let chagim = AlarmLogic.getChagim()
        print(chagim.map(\.desc))
        //TODO also delete any alarms not in chagim, for when user goes to israel
        for chag in chagim {
            await initializeAlarm(modelContext: modelContext, alarms: alarms, hEvent: chag)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to initialize: \(error)")
        }
    }
    
    static func initializeAlarm(modelContext: ModelContext, alarms: [AlarmModel], hEvent: HEvent) async {
        var alarm = alarms.first(where: { $0.name == hEvent.desc })
        if alarm == nil {
            alarm = AlarmModel(
                name: hEvent.desc,
                hour: 8,
                minute: 0,
                nextDayToFire: hEvent.hdate.greg()
            )
            modelContext.insert(alarm!)
        } else {
            alarm!.nextDayToFire = hEvent.hdate.greg()
        }
        await AlarmLogic.scheduleAlarm(alarm: alarm!)
    }
    
    @MainActor
    private func requestAlarmAuthorization() async throws {
        let status = try await AlarmManager.shared.requestAuthorization()
        switch status {
        case .authorized:
            break
        case .denied:
            showPermissionsDeniedAlert = true
            throw AlarmError.permissionDenied
        case .notDetermined:
            showPermissionsDeniedAlert = true
            throw AlarmError.permissionDenied
        @unknown default:
            showPermissionsDeniedAlert = true
            throw AlarmError.permissionDenied
        }
    }
}

enum AlarmError: Error, Sendable {
    case permissionDenied
    case ugh
}

#Preview {
    EditAlarmView()
        .modelContainer(for: AlarmModel.self, inMemory: true)
}
