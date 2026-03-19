import SwiftUI
import ActivityKit
import SwiftData
import AlarmKit
import Foundation
import Hebcal
import OSLog

struct EditAlarmView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let editingAlarm: AlarmModel?
    
    //TODO reduce boilerplate?
    @State private var alarmName = ""
    @State private var alarmType = AlarmType.explicit
    @State private var selectedTime = Testable.Date()
    @State private var duration: TimeInterval?
    @State private var repetitions: Int = -1
    @State private var repetitionDelay: TimeInterval = -1
    @State private var isEnabled: Bool = true
    @State private var isOverridden: Bool = true
    @State private var isGrouped: Bool = true
    @State private var maybeDayToFire: Date = Testable.Date()
    @State private var nextDayToFire: Date = Testable.Date()
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
                    isOverridden: $isOverridden,
                    isGrouped: $isGrouped,
                    maybeDayToFire: $maybeDayToFire,
                    nextDayToFire: $nextDayToFire,
                    daysOfWeek: $daysOfWeek
                )
                SoundSelectionView(selectedSound: $selectedSound)
            }
            .navigationTitle(alarmType == .explicit ? (alarmName == AlarmLogic.Once && !isEnabled ? "One off template" : "One off alarm") : alarmType == .weekDay ? "Weekly alarms" : alarmName)
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture {
            }
            .onAppear {
                do {
                    try loadAlarmData()
                } catch {
                    Logger.shared.info("Could not load alarm data") //TODO dialog
                }
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
    
    private func loadAlarmData() throws {
        guard let alarm = editingAlarm else { return }
        
        alarmName = alarm.name
        alarmType = alarm.alarmType
        selectedSound = alarm.selectedSound
        isEnabled = alarm.isEnabled
        isOverridden = alarm.isOverridden
        isGrouped = alarm.isGrouped
        daysOfWeek = alarm.daysOfWeek
        
        let calendar = Calendar.current
        if alarmName == AlarmLogic.Once {
            alarm.hour = calendar.component(.hour, from: Testable.Date())
            alarm.minute = calendar.component(.minute, from: Testable.Date()) + 1
            isEnabled = true
        }
        selectedTime = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Testable.Date()) ?? Testable.Date()
        duration = alarm.duration
        repetitions = alarm.repetitions
        repetitionDelay = alarm.repetitionDelay
        maybeDayToFire = try AlarmLogic.getNextDayToFire(Testable.Date(), alarm)
        nextDayToFire = maybeDayToFire
    }
    
    @MainActor
    private func saveAlarm() async {
        do {
            try await requestAlarmAuthorization()
            
            if let editingAlarm = editingAlarm {
                let originalDayToFire = (editingAlarm.isEnabled && !isEnabled) || editingAlarm.nextDayToFire != nextDayToFire ? editingAlarm.nextDayToFire : nil
                let originalDaysOfWeek = editingAlarm.daysOfWeek
                editingAlarm.daysOfWeek = daysOfWeek
                editingAlarm.isEnabled = isEnabled
                editingAlarm.isOverridden = isOverridden
                editingAlarm.isGrouped = isGrouped
                editingAlarm.selectedSound = selectedSound
                editingAlarm.duration = duration
                editingAlarm.repetitions = repetitions
                editingAlarm.repetitionDelay = repetitionDelay
                editingAlarm.hour = Calendar.current.component(.hour, from: selectedTime)
                editingAlarm.minute = Calendar.current.component(.minute, from: selectedTime)
                editingAlarm.maybeDayToFire = maybeDayToFire
                editingAlarm.nextDayToFire = nextDayToFire
                //TODO should actually not save any changes if there's an exception in AlarmLogic
                try await AlarmLogic.saveAlarm(Testable.Date(), editingAlarm, originalDaysOfWeek, originalDayToFire)
            }
            dismiss()
        } catch {
            Logger.shared.info("Error saving alarm: \(error)")
        }
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

#Preview {
    EditAlarmView()
        .modelContainer(for: AlarmModel.self, inMemory: true)
}
