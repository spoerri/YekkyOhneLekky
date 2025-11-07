import SwiftUI
import ActivityKit
import SwiftData
import AlarmKit
import Foundation
import Hebcal

struct EditAlarmView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let editingAlarm: AlarmModel?
    
    @State private var alarmName = ""
    @State private var alarmType = -1
    @State private var selectedTime = Date()
    @State private var duration: TimeInterval = -1
    @State private var repetitions: Int = -1
    @State private var repetitionDelay: TimeInterval = -1
    @State private var isEnabled: Bool = true
    @State private var isGrouped: Bool = true
    @State private var nextDayToFire = Date()
    @State private var daysOfWeek = Set<String>()
    @State private var showPermissionsDeniedAlert = false
    @State private var selectedSound: String?
    
    init(editingAlarm: AlarmModel? = nil) {
        self.editingAlarm = editingAlarm
    }
    
    var body: some View {
        NavigationStack {
            Form {
                AlarmDetailsView(
                    alarmName: $alarmName,
                    alarmType: $alarmType,
                    selectedTime: $selectedTime,
                    duration: $duration,
                    repetitions: $repetitions,
                    repetitionDelay: $repetitionDelay,
                    isEnabled: $isEnabled,
                    isGrouped: $isGrouped,
                    nextDayToFire: $nextDayToFire,
                    daysOfWeek: $daysOfWeek
                )
                SoundSelectionView(selectedSound: $selectedSound)
            }
            .navigationTitle(alarmType == AlarmModel.explicit ? "One off alarm" : alarmName)
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
        isEnabled = alarm.isEnabled
        isGrouped = alarm.isGrouped
        daysOfWeek = alarm.daysOfWeek
        
        let calendar = Calendar.current
        if alarmName == AlarmLogic.Once {
            alarm.hour = calendar.component(.hour, from: Date())
            alarm.minute = calendar.component(.minute, from: Date()) + 1
            isEnabled = true
        }
        selectedTime = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? Date()
        duration = alarm.duration
        repetitions = alarm.repetitions
        repetitionDelay = alarm.repetitionDelay
        nextDayToFire = (try? AlarmLogic.getNextDayToFire(alarm)) ?? Date()
    }
    
    @MainActor
    private func saveAlarm() async {
        do {
            try await requestAlarmAuthorization()
            
            if let editingAlarm = editingAlarm {
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: selectedTime)
                let minute = calendar.component(.minute, from: selectedTime)
                
                let dayOfWeekType = AlarmModel.dayOfWeek
                if editingAlarm.alarmType == dayOfWeekType {
                    for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { $0.alarmType == dayOfWeekType })) {
                        if daysOfWeek.contains(alarm.name) {
                            await saveAlarm(alarm, hour, minute)
                        } else {
                            alarm.daysOfWeek.subtract(daysOfWeek)
                        }
                    }
                } else if editingAlarm.name == AlarmLogic.Once && isEnabled {
                    if let nextDayToFire = editingAlarm.nextDayToFire {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd"
                        let newAlarm = AlarmModel(
                            name: dateFormatter.string(from: nextDayToFire),
                            hour: hour,
                            minute: minute,
                            nextDayToFire: nextDayToFire
                        )
                        newAlarm.alarmType = AlarmModel.explicit
                        modelContext.insert(newAlarm)
                        await saveAlarm(newAlarm, hour, minute)
                        
                    }
                } else {
                    if editingAlarm.alarmType == AlarmModel.explicit {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd"
                        editingAlarm.name = dateFormatter.string(from: nextDayToFire)
                        await saveAlarm(editingAlarm, hour, minute)
                    } else if isGrouped && editingAlarm.name != AlarmLogic.Once {
                        let yomtovType = AlarmModel.yomtov
                        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { $0.alarmType == yomtovType && $0.isGrouped })) {
                            if alarm.name != AlarmLogic.Once {
                                await saveAlarm(alarm, hour, minute)
                            }
                        }
                    } else {
                        await saveAlarm(editingAlarm, hour, minute)
                    }
                }
                
                try modelContext.save()
            }
            
            dismiss()
        } catch {
            print("Error saving alarm: \(error)")
        }
    }
    
    private func saveAlarm(_ alarm: AlarmModel, _ hour: Int, _ minute: Int) async {
        alarm.unschedule()
        alarm.hour = hour
        alarm.minute = minute
        alarm.isEnabled = isEnabled
        alarm.isGrouped = isGrouped
        alarm.daysOfWeek = daysOfWeek
        alarm.selectedSound = selectedSound
        alarm.duration = duration
        alarm.repetitions = repetitions
        alarm.repetitionDelay = repetitionDelay
        await AlarmLogic.schedule(alarm)
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
