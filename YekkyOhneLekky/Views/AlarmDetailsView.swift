import SwiftUI

struct AlarmDetailsView: View {
    @Binding var alarmName: String
    @Binding var alarmType: Int
    @Binding var selectedTime: Date
    @Binding var duration: TimeInterval
    @Binding var repetitions: Int
    @Binding var repetitionDelay: TimeInterval
    @Binding var isEnabled: Bool
    @Binding var isGrouped: Bool
    @Binding var nextDayToFire: Date
    @Binding var daysOfWeek: Set<String>
    
    var body: some View {
        Section(header: Text("Alarm Details")) {
            if alarmName != AlarmLogic.Once || isEnabled {
                DatePicker(alarmName != AlarmLogic.Once && alarmType != AlarmModel.explicit ? "Next date" : "Date",
                           selection: $nextDayToFire, displayedComponents: .date)
                    .disabled(alarmName != AlarmLogic.Once && alarmType != AlarmModel.explicit)
            }
            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute).onChange(of: selectedTime) {
                if alarmName != AlarmLogic.Once {
                    isEnabled = true
                }
            }
            Toggle("Enabled", isOn: $isEnabled)
            if alarmType == AlarmModel.yomtov && alarmName != AlarmLogic.Once {
                Toggle("Configured with other yomim tovim", isOn: $isGrouped)
            }
            Picker("Duration", selection: $duration) {
                ForEach(0..<10) { n in
                    if n == 0 {
                        Text("30 seconds").tag(TimeInterval(30))
                    } else {
                        Text("^[\(n) minutes](inflect: true)").tag(TimeInterval(n*60))
                    }
                }
            }.pickerStyle(.menu)
            Picker("Repetitions", selection: $repetitions) {
                ForEach(0..<10) { n in
                    Text("^[\(n) extra times](inflect: true)").tag(n)
                }
            }.pickerStyle(.menu)
            Picker("Repetition delay", selection: $repetitionDelay) {
                ForEach(0..<10) { n in
                    if n == 0 {
                        Text("30 seconds").tag(TimeInterval(30))
                    } else {
                        Text("^[\(n) minutes](inflect: true)").tag(TimeInterval(n*60))
                    }
                }
            }.pickerStyle(.menu).disabled(repetitions == 0)
            if alarmType == AlarmModel.dayOfWeek {
                StatefulPreviewWrapper() { _ in DaysOfWeekView(selectedDays: $daysOfWeek, alarmName: alarmName) }
            }
        }
    }
}

let allDaysOfWeek = AlarmLogic.allDaysOfWeek

struct DaysOfWeekView: View {
    @Binding var selectedDays: Set<String>
    var alarmName: String

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<allDaysOfWeek.count, id: \.self) { day in
                Button(action: {
                    if selectedDays.contains(allDaysOfWeek[day]) {
                        selectedDays.remove(allDaysOfWeek[day])
                    } else {
                        selectedDays.insert(allDaysOfWeek[day])
                    }
                }) {
                    Text(Calendar.current.veryShortWeekdaySymbols[day])
                        .fontWeight(.bold)
                        .frame(width: 36, height: 36)
                        .foregroundColor(selectedDays.contains(allDaysOfWeek[day]) ? .white : .primary)
                        .background(selectedDays.contains(allDaysOfWeek[day]) ? Color.accentColor : Color(.systemGray5))
                        .clipShape(Circle())
                }
                .disabled(allDaysOfWeek[day] == alarmName)
                .buttonStyle(PlainButtonStyle())
            }
        }.task {
            selectedDays.insert(alarmName)
        }
    }
}

struct StatefulPreviewWrapper<Content: View>: View {
    @State var value: Set<String>
    var content: (Binding<Set<String>>) -> Content

    init(content: @escaping (Binding<Set<String>>) -> Content) {
        self._value = State(initialValue: Set(allDaysOfWeek))
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
