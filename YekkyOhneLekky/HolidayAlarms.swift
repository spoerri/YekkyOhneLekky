import ActivityKit
import AlarmKit
import AVFoundation
import Hebcal
internal import SwiftUI

class HolidayAlarms {
    public static var Shabbos = "Shabbos"
    public static var Today = "Today"
    
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
        }x
//        print("This year's \(thisYears.map{ $0.hdate.greg() })")
        let hebrewDateNextYear = HDate(yy:htoday.yy+1, mm:htoday.mm, dd:htoday.dd)
        var nextYears = Hebcal.getAllHolidaysForYear(year: htoday.yy+1)
        nextYears = nextYears.filter {
            ((il && !$0.flags.contains(.CHUL_ONLY)) || (!il && !$0.flags.contains(.IL_ONLY)))
            && $0.flags.contains(.CHAG)
            && $0.hdate < hebrewDateNextYear
        }
//        print("Next year's \(nextYears.map{ $0.hdate.greg() })")
        return thisYears + nextYears + [HEvent.init(hdate: htoday, desc: Today)]
    }
    
    public class func getDate(nameOfChag: String) -> Date? {
        if nameOfChag == Shabbos {
            return Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 7), matchingPolicy: .nextTimePreservingSmallerComponents)
        }
        if nameOfChag == Today {
            return Date()
        }
        return getChagim().filter { $0.desc == nameOfChag }.first!.hdate.greg()
    }
    
    public class func scheduleAlarm(alarm: AlarmModel) async {
        do {
            let schedule = getSchedule(alarm: alarm)
            
            let stopButton = AlarmButton(
                text: "",
                textColor: .black,
                systemImageName: "checkmark.seal.fill"
            )
            
            let alertPresentation = AlarmPresentation.Alert(
                title: getSalutation(alarm: alarm),
                stopButton: stopButton
            )
            
            let presentation = AlarmPresentation(
                alert: alertPresentation
            )
            
            struct EmptyMetadata : AlarmMetadata {
            }
            
            //TODO use the intent api so that touching will open the app - for after shabbos/yomtov
            //TODO use a brighter color and reminder for getting close to the end of the year
            
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: EmptyMetadata(),
                tintColor: .black
            )
            
            let soundConfig: AlertConfiguration.AlertSound
            if let selectedSoundName = alarm.selectedSound {
                // Verify the sound file exists
                if let soundURL = Bundle.main.url(forResource: selectedSoundName, withExtension: "mp3") {
                    soundConfig = AlertConfiguration.AlertSound.named("airhorn.mp3")
                    //soundConfig = AlertConfiguration.AlertSound.named(selectedSoundName)
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
    
    public class func getSchedule(alarm: AlarmModel) -> Alarm.Schedule? {
        if alarm.name == Shabbos { //TODO should probably just go and schedule 50, at least so that we can handle shabbos on yom tov
            return Alarm.Schedule.relative(.init(time: Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute), repeats: Alarm.Schedule.Relative.Recurrence.weekly([Locale.Weekday.saturday])))
        } else {
            //TODO is this daylight savings friendly?
            guard let dateAndTime = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second:0, of: alarm.nextDayToFire!, matchingPolicy: .nextTime) else {
                print("Failed to figure alarm time for \(alarm.name)");
                return nil
            }
            return Alarm.Schedule.fixed(dateAndTime)
        }
    }
    
    public class func getSalutation(alarm: AlarmModel) -> LocalizedStringResource {
        if alarm.name == Shabbos {
            return "Gut shabbes!"
        } else {
            return "Gut yontif!"
        }
    }
}

//TODO error message: Potential Structural Swift Concurrency Issue: unsafeForcedSync called from Swift Concurrent context.
