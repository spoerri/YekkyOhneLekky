import SwiftUI
import ActivityKit
import AlarmKit
import AppIntents
import SwiftData

let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
let versionLastRunKey = "versionLastRun"

struct ContentView: View {
    @State private var showModal = UserDefaults.standard.string(forKey: versionLastRunKey) != version
    var body: some View {
        AlarmListView(showModal: $showModal)
            .sheet(isPresented: $showModal) {
                ModalView()
            }
    }
}

struct ModalView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("בס'ד").padding(.horizontal).frame(maxWidth: .infinity, alignment: .trailing)
            ScrollView {
                Text("""
YekkyOhneLekky provides shabbos and yom tov wake-up alarms that don't bother people by ringing for 15 minutes. You can make them as short as 30 seconds, and you can make them repeat. We strongly recommend that you leave your phone in a different place on erev shabbos than the place that you do on weeknights, a place which is not reachable from bed!

YekkyOhneLekky also automatically sets jewish holiday alarms appropriately based on the jewish calendar. If you go to the same minyan for each holiday from year to year, you'll never have to worry about resetting that alarm; it'll continue to ring at the same time automatically on the right date each year.

YekkyOhneLekky can even relieve you of turning off your regular weekday alarms before holidays. Put those alarms in Yekky instead of Apple's standard Clock, and they'll only be used on non-holidays. It also supports "one off" alarms that override any of the above. You can use this feature to test alarms when you first start using the app.

For now, please remember to continue manually maintaining your alarms for legal holidays, minor holidays, rosh chodesh, alos minyanim, and any day with selichos.

I hope you enjoy it! With love, and with gratitude to the boreh olam, Joshua Spoerri
""").padding()
                HStack {
                    Spacer()
                    Link("Contact me", destination: URL(string: "mailto:spoerri@gmail.com?subject=YekkyOhneLekky    ")!)
                    Spacer()
                    Button("Dismiss") {
                        dismiss()
                        UserDefaults.standard.set(version, forKey: versionLastRunKey)
                    }
                    Spacer()
                    Button("Donate") {}
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AlarmModel.self, inMemory: true)
}
