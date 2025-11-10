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

YekkyOhneLekky can even relieve you of turning off your regular weekday alarms before holidays. Put those alarms in Yekky instead of Apple's standard Clock, and they'll only be used on non-holidays. It supports alarms for US national holidays, as well as rosh chodesh, fasts, and holidays without an issur melacha. It also supports "one off" alarms that override any of the above. You can use this feature to test alarms when you first start using the app.

For now, please remember to manually update your alarms for yomim noraim selichos, behab, minyanim that are close to zman talis or zman kriyas shema, and anything you don't see an entry for in the app.

The app should not have to be running in order for alarms to sound, or for subsequent alarms to be scheduled. The only exception is if the app is not running and your phone is entirely off when an alarm is scheduled to run. In this case, just start Yekky after you turn your phone on.

Yekky should be smart about multiple alarms occurring on the same day; it prefers the sensible one. “One off”s beat yom tov, yom tov beats shabbos, shabbos beats national holidays, national holidays beat rosh chodesh, and rosh chodesh beats weekdays (eg Tuesday). (Fasts and chol hamoed have the same precedence as rosh chodesh. Sundays have the same precedence as national holidays.) The simple explanation is that on “work days”, shacharis is often scheduled to enable people to get to work on time. Disabling a higher precedence alarm doesn't currently restore a lower precedence alarm automatically.

I hope you enjoy it!

With love, and with gratitude to the boreh olam, Joshua Spoerri
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
                    Button("Donate") {}.disabled(true)
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
