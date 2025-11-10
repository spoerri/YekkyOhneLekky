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
    @State private var alarmType = AlarmType.explicit
    @State private var selectedTime = Date()
    @State private var duration: TimeInterval?
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
            .navigationTitle(alarmType == .explicit ? "One off alarm" : alarmType == .weekDay ? "Weekly alarms" : alarmName)
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
        nextDayToFire = AlarmLogic.getNextDayToFire(alarm) ?? Date()
    }
    
    @MainActor
    private func saveAlarm() async {
        do {
            try await requestAlarmAuthorization()
            
            if let editingAlarm = editingAlarm {
                let calendar = Calendar.current
                editingAlarm.hour = calendar.component(.hour, from: selectedTime)
                editingAlarm.minute = calendar.component(.minute, from: selectedTime)
                
                if editingAlarm.alarmType == .weekDay && !daysOfWeek.isEmpty {
                    let removedDays = editingAlarm.daysOfWeek.subtracting(daysOfWeek)
                    if !removedDays.isEmpty {
                        let newAlarm = AlarmModel(
                            name: "",
                            alarmType: .weekDay,
                            hour: editingAlarm.hour,
                            minute: editingAlarm.minute
                        )
                        populateAlarm(newAlarm)
                        newAlarm.daysOfWeek = removedDays
                        newAlarm.setNameFromDaysOfWeek()
                        newAlarm.isEnabled = false
                        modelContext.insert(newAlarm)
                    }
                    for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>()) {
                        if !daysOfWeek.isDisjoint(with: alarm.daysOfWeek) && alarm != editingAlarm {
                            alarm.unschedule()
                            alarm.daysOfWeek.subtract(daysOfWeek)
                            if alarm.daysOfWeek.isEmpty {
                                modelContext.delete(alarm)
                            } else {
                                alarm.setNameFromDaysOfWeek()
                                await AlarmLogic.schedule(alarm)
                            }
                        }
                    }
                    populateAlarm(editingAlarm)
                    editingAlarm.setNameFromDaysOfWeek()
                    await AlarmLogic.schedule(editingAlarm)
                } else if editingAlarm.name == AlarmLogic.Once && isEnabled {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let newAlarm = AlarmModel(
                        name: dateFormatter.string(from: nextDayToFire),
                        alarmType: AlarmType.explicit,
                        hour: editingAlarm.hour,
                        minute: editingAlarm.minute
                    )
                    modelContext.insert(newAlarm)
                    populateAlarm(newAlarm)
                    newAlarm.isGrouped = true
                    await AlarmLogic.schedule(newAlarm)
                } else if isGrouped {
                    var alarms = Set(try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { $0.isGrouped })))
                    alarms.insert(editingAlarm)
                    for alarm in alarms {
                        if alarm.alarmType == editingAlarm.alarmType {
                            await reschedule(alarm)
                        }
                    }
                } else {
                    await reschedule(editingAlarm)
                }
                
                try modelContext.save()
            }
            
            dismiss()
        } catch {
            print("Error saving alarm: \(error)")
        }
    }
    
    private func reschedule(_ alarm: AlarmModel) async {
        alarm.unschedule()
        if alarm.name != AlarmLogic.Once && alarm.alarmType == AlarmType.explicit {
            if let nextDayToFire = alarm.nextDayToFire {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                alarm.name = dateFormatter.string(from: nextDayToFire)
            }
        }
        populateAlarm(alarm)
        await AlarmLogic.schedule(alarm)
    }
    
    private func populateAlarm(_ alarm: AlarmModel) {
        alarm.isEnabled = isEnabled
        alarm.isGrouped = isGrouped
        alarm.daysOfWeek = daysOfWeek
        alarm.selectedSound = selectedSound
        alarm.duration = duration
        alarm.repetitions = repetitions
        alarm.repetitionDelay = repetitionDelay
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
