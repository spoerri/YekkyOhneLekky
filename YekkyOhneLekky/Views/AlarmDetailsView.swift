import SwiftUI

struct AlarmDetailsView: View {
    @Binding var alarmName: String
    @Binding var selectedTime: Date
    @Binding var isActive: Bool
    @Binding var nextDayToFire: String
    
    var body: some View {
        Section(header: Text("Alarm Details")) {
            Text(alarmName)
            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
            Toggle("Enabled", isOn: $isActive)
            LabeledContent("Next date", value: nextDayToFire)
        }
    }
}
