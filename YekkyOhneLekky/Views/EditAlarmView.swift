internal import SwiftUI
internal import SwiftData
import AlarmKit //TODO move the alarmkit stuff into a separate class
import Foundation
import Hebcal

struct EditAlarmView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let editingAlarm: AlarmModel?
    
    @State private var alarmName = ""
    @State private var selectedTime = Date()
    @State private var nextDayToFire: String
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
                AlarmDetailsSection(
                    alarmName: $alarmName,
                    selectedTime: $selectedTime,
                    nextDayToFire: $nextDayToFire
                )
                
                SoundSelectionSection(selectedSound: $selectedSound)
                //TODO support for an "enabled" toggle
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
        selectedSound = alarm.selectedSound
        
        let calendar = Calendar.current
        selectedTime = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? Date()
    }
    
    @MainActor
    private func saveAlarm() async {
        do {
            try await requestAlarmAuthorization()
            
//            print("alarms:", try AlarmManager.shared.alarms)
            
            if let editingAlarm = editingAlarm {
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: selectedTime)
                let minute = calendar.component(.minute, from: selectedTime)
                editingAlarm.hour = hour
                editingAlarm.minute = minute
                editingAlarm.selectedSound = selectedSound
                editingAlarm.nextDayToFire = HolidayAlarms.getDate(nameOfChag: alarmName)! //TODO error handling
//                editingAlarm.nextDayToFire = Date() //should be commented out! otherwise for testing
                
                do {
                    try AlarmManager.shared.stop(id: editingAlarm.id)
                } catch {
                    print("could not cancel \(editingAlarm.id)")
                }
                
                //TODO check if alarm is in the past
                
                await HolidayAlarms.scheduleAlarm(alarm: editingAlarm)
                
                try modelContext.save()
            }
            
            dismiss()
        } catch {
            print("Error saving alarm: \(error)")
        }
    }
    
    public static func scheduleNext(modelContext: ModelContext, alarms: [AlarmModel]) async {
        print("\(Date()) Rescheduling: \(alarms.map{ $0.name})")
        for alarm in alarms {
            alarm.nextDayToFire = HolidayAlarms.getDate(nameOfChag: alarm.name)
        }
        do {
            try modelContext.save()
        } catch {
            print("Error scheduling next alarm: \(error)")
        }
        for alarm in alarms {
            do {
                try AlarmManager.shared.stop(id: alarm.id)
            } catch {
            }
            await HolidayAlarms.scheduleAlarm(alarm: alarm)
        }
    }
    
    public static func initializeAlarms(modelContext: ModelContext, alarms: [AlarmModel]) async {
        do {
            for alarm in try AlarmManager.shared.alarms {
                try AlarmManager.shared.cancel(id:alarm.id)
            }
        } catch {
            print("Could not cancel all alarms")
        }
        
        await createIfNesc(modelContext: modelContext, alarms: alarms, alarmName: HolidayAlarms.Shabbos)
        
        let chagim = HolidayAlarms.getChagim()
        print(chagim.map(\.desc))
        //TODO also delete any alarms not in chagim, for when user goes to israel
        for chag in chagim {
            await createIfNesc(modelContext: modelContext, alarms: alarms, alarmName: chag.desc)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to initialize: \(error)")
        }
    }
    
    static func createIfNesc(modelContext: ModelContext, alarms: [AlarmModel], alarmName: String) async {
        var alarm = alarms.first(where: { $0.name == alarmName})
        if alarm == nil {
            alarm = AlarmModel(
                name: alarmName,
                hour: 8,
                minute: 0,
                nextDayToFire: nil
            )
            modelContext.insert(alarm!)
        }
            
        alarm!.nextDayToFire = HolidayAlarms.getDate(nameOfChag: alarmName)
        await HolidayAlarms.scheduleAlarm(alarm: alarm!)
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
