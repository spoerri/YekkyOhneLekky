internal import SwiftUI
internal import SwiftData

@main
struct YekkyOhneLekkyApp: App {
    let container: ModelContainer
    
    init() {
        do {
            container = try ModelContainer(for: AlarmModel.self)
        } catch {
            fatalError("Failed to initialize ModelContainer")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
