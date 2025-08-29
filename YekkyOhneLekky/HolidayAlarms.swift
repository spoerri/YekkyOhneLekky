import ActivityKit
import AlarmKit
import AVFoundation
import Hebcal

class HolidayAlarms {
    public static var Shabbos = "Shabbos"
    
    public class func getChagim() -> [HEvent] {
        //TODO allow overriding israel
        let il = Locale.current.region == Locale.Region.israel
        //TODO extract a method?
        let today = Calendar.current.date(byAdding: .month, value: 0, to:Date())! //verbose to ease testing
        let htoday = HDate(date: today, calendar: .current)
        var thisYears = Hebcal.getAllHolidaysForYear(year: htoday.yy)
        thisYears = thisYears.filter {
            ((il && !$0.flags.contains(.CHUL_ONLY)) || (!il && !$0.flags.contains(.IL_ONLY)))
            && $0.flags.contains(.CHAG)
            && $0.hdate > htoday
        }
//        print("This year's \(thisYears.map{ $0.hdate.greg() })")
        let hebrewDateNextYear = HDate(yy:htoday.yy+1, mm:htoday.mm, dd:htoday.dd)
        var nextYears = Hebcal.getAllHolidaysForYear(year: htoday.yy+1)
        nextYears = nextYears.filter {
            ((il && !$0.flags.contains(.CHUL_ONLY)) || (!il && !$0.flags.contains(.IL_ONLY)))
            && $0.flags.contains(.CHAG)
            && $0.hdate < hebrewDateNextYear
        }
//        print("Next year's \(nextYears.map{ $0.hdate.greg() })")
        return thisYears + nextYears
    }
    
    public class func getDate(nameOfChag: String) -> Date? {
        if nameOfChag == Shabbos {
            return Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 7), matchingPolicy: .nextTimePreservingSmallerComponents)
        }
        return getChagim().filter { $0.desc == nameOfChag }.first!.hdate.greg()
    }
    
    public class func scheduleAlarm(alarm: AlarmModel) async {
        do {
            //TODO is this daylight savings friendly?
            guard let dateAndTime = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second:0, of: alarm.nextDayToFire!, matchingPolicy: .nextTime) else {
                print("Failed to figure alarm time for \(alarm.name)"); return
            }
            let schedule = Alarm.Schedule.fixed(dateAndTime)
            
            let stopButton = AlarmButton(
                text: "",
                textColor: .black,
                systemImageName: "checkmark.seal.fill"
            )
            
            let alertPresentation = AlarmPresentation.Alert(
                title: "Good morning!",
                stopButton: stopButton
            )
            
            let presentation = AlarmPresentation(
                alert: alertPresentation
            )
            
            struct EmptyMetadata : AlarmMetadata {
            }
            
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: EmptyMetadata(),
                tintColor: .black
                //TODO get rid of the grey tint to truly hide the button?
            )
            
            let soundConfig: AlertConfiguration.AlertSound
            if let selectedSoundName = alarm.selectedSound {
                // Verify the sound file exists
                if let soundURL = Bundle.main.url(forResource: selectedSoundName, withExtension: "mp3") { //TODO use it?
                    soundConfig = AlertConfiguration.AlertSound.named(selectedSoundName)
                } else {
                    soundConfig = .default
                    print("Custom sound \(selectedSoundName).mp3 not found in bundle, using default")
                }
            } else {
                soundConfig = .default
            }
//            print("Using sound: \(soundConfig)")
            
            let alarmConfiguration = AlarmManager.AlarmConfiguration(
                schedule: schedule,
                attributes: attributes,
                sound: soundConfig
            )
            
//            print("\(Date()) Scheduling alarm with ID: \(alarm.id) for \(schedule)")
            print("\(Date()) Scheduling for \(schedule)")
            _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: alarmConfiguration)
            
        } catch {
            print("\(Date()) Error scheduling alarm: \(error)")
        }
    }
}
