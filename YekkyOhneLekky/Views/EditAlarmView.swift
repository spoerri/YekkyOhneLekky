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
    
    let editingAlarm: AlarmModel
    
    @State private var alarmName: String
    @State private var alarmType: AlarmType
    @State private var selectedTime: Date
    @State private var duration: TimeInterval?
    @State private var repetitions: Int
    @State private var repetitionDelay: TimeInterval
    @State private var isEnabled: Bool
    @State private var isOverridden: Bool
    @State private var isExtra: Bool
    @State private var isGrouped: Bool
    @State private var maybeDayToFire: String
    @State private var nextDayToFire: String
    @State private var daysOfWeek: Set<String>
    @State private var selectedSound: String?
    
    @State private var showPermissionsDeniedAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                SoundSelectionView(selectedSound: $selectedSound)
            }
            .navigationTitle(alarmType == .explicit ? (alarmName == AlarmLogic.Once && !isEnabled ? "One off template" : "One off alarm") : alarmType == .weekDay ? "Weekly alarms" : alarmName)
            .navigationBarTitleDisplayMode(.inline)
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
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section(header: Text("Alarm Details")) {
            if alarmName != AlarmLogic.Once || isEnabled {
                if alarmName == AlarmLogic.Once || alarmType == .explicit {
                    let datePickerInterceptor = Binding<Date>(
                        get: { AlarmModel.date(nextDayToFire) },
                        set: {
                            nextDayToFire = AlarmModel.day($0)
                            maybeDayToFire = nextDayToFire //a picked day isn't overridden
                            //default to the time of the alarm to be overridden
                            if alarmName == AlarmLogic.Once {
                                let day = nextDayToFire
                                if let existingAlarm = try? modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> {$0.nextDayToFire == day && $0.name != alarmName && $0.maybeDayToFire == $0.nextDayToFire})).first {
                                    if existingAlarm.nextDayToFire != AlarmModel.day(Testable.Date()) {
                                        do {
                                            selectedTime = try existingAlarm.getAlarmDateAndTime()
                                        } catch {
                                            AlarmLogger.shared.error("Error getting time of alarm: \(error)")
                                        }
                                    }
                                }
                            }
                        }
                    )
                    DatePicker("Date", selection: datePickerInterceptor, displayedComponents: .date)
                } else {
                    HStack {
                        Text("Next date:")
                        Text(AlarmModel.date(maybeDayToFire), formatter: dateFormatter)
                            .strikethrough(isOverridden).frame(maxWidth: .infinity, alignment: .trailing)
                        //TODO show the nextDayToFire (not strikethrough) if maybeDayToFire is overridden
                        //TODO be clever about two day rosh chodesh?
                    }
                }
            }
            if let groupLabel = AlarmLogic.groupLabel[alarmType] {
                if alarmName != AlarmLogic.Once || isEnabled { //the one-off template isn't grouped with the actual one-offs
                    Toggle("Configured with other "+groupLabel, isOn: $isGrouped)
                }
            }
            if alarmName != AlarmLogic.Once || isEnabled {
                DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
            }
            if alarmType == .explicit {
                Toggle("Extra (e.g. for a nap)", isOn: $isExtra)
            }
            Toggle("Enabled", isOn: $isEnabled)
                .onChange(of: isEnabled, initial: true) {
                    if alarmName == AlarmLogic.Once {
                        isGrouped = isEnabled
                    }
                }
            Picker("Duration", selection: $duration) {
                Text("30 seconds").tag(TimeInterval(30))
                Text("1 minute").tag(TimeInterval(60))
                Text("2 minutes").tag(TimeInterval(120))
                Text("4 minutes").tag(TimeInterval(240))
                Text("8 minutes").tag(TimeInterval(480))
                Text("15 minutes").tag(nil as TimeInterval?)
            }.pickerStyle(.menu)
            Picker("Repetitions", selection: $repetitions) {
                ForEach(0..<10) { n in
                    Text("^[\(n) extra times](inflect: true)").tag(n)
                }
            }.pickerStyle(.menu)
                .onChange(of: repetitions) {
                    if repetitions > 0 && duration == nil {
                        duration = TimeInterval(60)
                    }
                }
            Picker("Repetition delay", selection: $repetitionDelay) {
                Text("30 seconds").tag(TimeInterval(30))
                Text("1 minute").tag(TimeInterval(60))
                Text("2 minutes").tag(TimeInterval(120))
                Text("4 minutes").tag(TimeInterval(240))
                Text("8 minutes").tag(TimeInterval(480))
                Text("15 minutes").tag(TimeInterval(900))
            }.pickerStyle(.menu).disabled(repetitions == 0)
            if alarmType == .weekDay {
                HStack(spacing: 14) {
                    ForEach(0..<AlarmLogic.allDaysOfWeek.count, id: \.self) { day in
                        Button(action: {
                            if daysOfWeek.contains(AlarmLogic.allDaysOfWeek[day]) {
                                daysOfWeek.remove(AlarmLogic.allDaysOfWeek[day])
                            } else {
                                daysOfWeek.insert(AlarmLogic.allDaysOfWeek[day])
                            }
                        }) {
                            Text(Calendar.current.veryShortWeekdaySymbols[day])
                                .fontWeight(.bold)
                                .frame(width: 36, height: 36)
                                .foregroundColor(daysOfWeek.contains(AlarmLogic.allDaysOfWeek[day]) ? .white : .primary)
                                .background(daysOfWeek.contains(AlarmLogic.allDaysOfWeek[day]) ? Color.accentColor : Color(.systemGray5))
                                .clipShape(Circle())
                        }
                        .disabled(AlarmLogic.allDaysOfWeek[day] == AlarmLogic.Saturday)
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    init(editingAlarm: AlarmModel) {
        self.editingAlarm = editingAlarm
        
        alarmName = editingAlarm.name
        alarmType = editingAlarm.alarmType
        selectedSound = editingAlarm.selectedSound
        isEnabled = editingAlarm.isEnabled
        isOverridden = editingAlarm.isOverridden
        isExtra = editingAlarm.isExtra
        isGrouped = editingAlarm.isGrouped
        daysOfWeek = editingAlarm.daysOfWeek
        
        if editingAlarm.name == AlarmLogic.Once {
            selectedTime = Calendar.current.date(byAdding: .minute, value:1, to: Testable.Date())!
            isEnabled = true
            isExtra = false
        } else {
            do {
                selectedTime = try editingAlarm.getAlarmDateAndTime()
            } catch {
                selectedTime = Testable.Date()
                AlarmLogger.shared.error("Error editing alarm: \(error)")
            }
        }
        duration = editingAlarm.duration
        repetitions = editingAlarm.repetitions
        repetitionDelay = editingAlarm.repetitionDelay
        let day: String
        do {
            day = try AlarmLogic.getNextDayToFire(Testable.Date(), editingAlarm)
        } catch {
            day = AlarmModel.day(Testable.Date())
            AlarmLogger.shared.error("Error editing alarm: \(error)")
        }
        maybeDayToFire = day
        nextDayToFire = day
    }
    
    @MainActor
    private func saveAlarm() async {
        do {
            try await requestAlarmAuthorization()
            let originalDayToFire = (editingAlarm.isEnabled && !isEnabled)
                || (!editingAlarm.isExtra && isExtra)
                || editingAlarm.nextDayToFire != nextDayToFire
                ? editingAlarm.nextDayToFire : nil
            let originalDaysOfWeek = editingAlarm.daysOfWeek
            editingAlarm.daysOfWeek = daysOfWeek
            editingAlarm.isEnabled = isEnabled
            editingAlarm.isExtra = isExtra
            editingAlarm.isGrouped = isGrouped
            editingAlarm.selectedSound = selectedSound
            editingAlarm.duration = duration
            editingAlarm.repetitions = repetitions
            editingAlarm.repetitionDelay = repetitionDelay
            editingAlarm.hour = Calendar.current.component(.hour, from: selectedTime)
            editingAlarm.minute = Calendar.current.component(.minute, from: selectedTime)
            editingAlarm.maybeDayToFire = maybeDayToFire
            editingAlarm.nextDayToFire = nextDayToFire
            AlarmLogger.shared.info("saveAlarm: \(editingAlarm.name)")
            //TODO should actually not save any changes if there's an exception in AlarmLogic
            try await AlarmLogic.saveAlarm(Testable.Date(), modelContext, editingAlarm, originalDaysOfWeek, originalDayToFire)
            dismiss()
        } catch {
            AlarmLogger.shared.error("Error saving alarm: \(error)")
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
    @Previewable @State var value = AlarmModel(name: "Preview Alarm", alarmType: AlarmType.explicit, hour: 8, minute: 0, maybeDayToFire: AlarmModel.day(Date()), nextDayToFire: AlarmModel.day(Date()))
    EditAlarmView(editingAlarm: value)
        .modelContainer(for: AlarmModel.self, inMemory: true)
}
