import SwiftUI

struct AlarmDetailsView: View {
    @Binding var alarmName: String
    @Binding var alarmType: Int
    @Binding var selectedTime: Date
    @Binding var isActive: Bool
    @Binding var nextDayToFire: String
    @Binding var daysOfWeek: Set<String>
    
    var body: some View {
        Section(header: Text("Alarm Details")) {
            Text(alarmName)
            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
            //TODO repetitions etc
            Toggle("Enabled", isOn: $isActive)
            LabeledContent("Next date", value: nextDayToFire)
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
