import SwiftUI
import ActivityKit
import AlarmKit
import AppIntents

struct ContentView: View {
    @State private var observable = AlarmUpdatesObservable()
    
    var body: some View {
        AlarmListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AlarmModel.self, inMemory: true)
}
