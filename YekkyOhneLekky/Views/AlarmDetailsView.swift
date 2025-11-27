import SwiftUI

struct AlarmDetailsView: View {
    @Binding var alarmName: String
    @Binding var alarmType: AlarmType
    @Binding var selectedTime: Date
    @Binding var duration: TimeInterval?
    @Binding var repetitions: Int
    @Binding var repetitionDelay: TimeInterval
    @Binding var isEnabled: Bool
    @Binding var isOverridden: Bool
    @Binding var isGrouped: Bool
    @Binding var nextDayToFire: Date
    @Binding var daysOfWeek: Set<String>
    @State private var initialSelectedTime: Date = Date.distantPast
    
    private var dateFormatter: DateFormatter {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return formatter
            }
    
    var body: some View {
        Section(header: Text("Alarm Details")) {
            if alarmName != AlarmLogic.Once || isEnabled {
                if alarmName == AlarmLogic.Once || alarmType == .explicit {
                        DatePicker("Date", selection: $nextDayToFire, displayedComponents: .date)
                } else {
                    HStack {
                        Text("Next date:")
                        Text(nextDayToFire, formatter: dateFormatter)
                            .strikethrough(isOverridden).frame(maxWidth: .infinity, alignment: .trailing)
                        //TODO be clever about two day rosh chodesh?
                    }
                }
            }
            if alarmName != AlarmLogic.Once || isEnabled {
                DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .onChange(of: selectedTime, initial: true) { //false doesn't work, so use initialSelectedTime var
                        if initialSelectedTime == Date.distantPast {
                            initialSelectedTime = selectedTime
                        } else if selectedTime != initialSelectedTime {
                            isEnabled = true
                            initialSelectedTime = selectedTime
                        }
                    }
            }
            Toggle("Enabled", isOn: $isEnabled)
                .onChange(of: isEnabled, initial: true) {
                    if alarmName == AlarmLogic.Once {
                        isGrouped = isEnabled
                    }
                }
            if let groupLabel = AlarmLogic.groupLabel[alarmType] {
                if alarmName != AlarmLogic.Once || isEnabled { //the one-off template isn't grouped with the actual one-offs
                    Toggle("Configured with other "+groupLabel, isOn: $isGrouped)
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
                .disabled(allDaysOfWeek[day] == AlarmLogic.Saturday)
                .buttonStyle(PlainButtonStyle())
            }
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
