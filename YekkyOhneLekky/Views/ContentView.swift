import SwiftUI
import ActivityKit
import AlarmKit
import AppIntents
import SwiftData

struct ContentView: View {
    var body: some View {
        AlarmListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AlarmModel.self, inMemory: true)
}
