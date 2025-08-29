internal import SwiftUI

struct AlarmDetailsSection: View {
    @Binding var alarmName: String
    @Binding var selectedTime: Date
    @Binding var nextDayToFire: String
    
    var body: some View {
        Section(header: Text("Alarm Details")) {
            Text(alarmName)
            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
            LabeledContent("Next date", value: nextDayToFire)
        }
    }
}
