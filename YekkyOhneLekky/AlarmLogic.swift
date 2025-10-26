import ActivityKit
import SwiftData
import AlarmKit
import AVFoundation
import Hebcal
import SwiftUI

class AlarmLogic {
    public static nonisolated let Once = "Just once"
    public static nonisolated let weekDays = Calendar.current.standaloneWeekdaySymbols
    
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
        
        return [HEvent.init(hdate: htoday, desc: Once)] + thisYears + nextYears
            + weekDays.map { HEvent.init(hdate: HDate(date: getNextDayOfWeek(nameOfDay: $0)!, calendar: .current), desc: $0) }
    }
    
    class func getNextDayOfWeek(nameOfDay: String) -> Date? {
        //TODO step 2 display checkboxes in those entries to also set other days
        //TODO step 3 smarter ui?
        
        for (index, name) in weekDays.enumerated() {
            if nameOfDay == name {
                return Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: index+1), matchingPolicy: .nextTimePreservingSmallerComponents)
            }
        }
        return nil
    }
    
    public class func getDate(nameOfAlarm: String) -> Date? {
        if nameOfAlarm == Once {
            return Date()
        }
        if let weekDay = getNextDayOfWeek(nameOfDay: nameOfAlarm) {
            return weekDay
        }
        return getChagim().filter { $0.desc == nameOfAlarm }.first!.hdate.greg()
    }
    
    class func isScheduled(_ alarm: AlarmModel) throws -> Bool {
        return try AlarmManager.shared.alarms.contains(where: { $0.id == alarm.id })
    }
    
    public class func scheduleAlarm(alarm: AlarmModel) async {
        do {
            if try isScheduled(alarm) || !alarm.isActive {
                return;
            }
            
            if (weekDays.contains(alarm.name)) {
                //TODO test this next
                //the app will always create the holiday entry for a day _before_ trying to create a day-of-week entry for it
                let alarmDate = alarm.nextDayToFire
                if let holiday = try alarm.modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { holiday in !weekDays.contains(holiday.name) && holiday.nextDayToFire == alarmDate })) {
                    let holidayName = holiday.first!.name
                    print("Not scheduling a "+alarm.name+" because there is a holiday, "+holidayName+", on that day: "+alarm.timeString)
                    return
                }
            }
            
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
            
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: EmptyMetadata(),
                tintColor: .black
            )
            
            let soundConfig: AlertConfiguration.AlertSound
            if let selectedSoundName = alarm.selectedSound {
                // Verify the sound file exists
                if let soundURL = Bundle.main.url(forResource: selectedSoundName, withExtension: "mp3") {
                    soundConfig = AlertConfiguration.AlertSound.named(selectedSoundName+".mp3")
                } else {
                    soundConfig = .default
                    print("Custom sound \(selectedSoundName).mp3 not found in bundle, using default")
                }
            } else {
                soundConfig = .default
            }
            
//                soundConfig = AlertConfiguration.AlertSound.named("sample.m4a")
            print("Using sound: \(soundConfig)")
            
            let alarmConfiguration = AlarmManager.AlarmConfiguration(
                schedule: schedule,
                attributes: attributes,
                stopIntent: ScheduleNextAlarmsIntent(alarmID: alarm.id.uuidString),
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
        //TODO test if the alarm is scheduled before daylight savings for after, or vice versa
        guard let dateAndTime = alarm.getAlarmDate() else {
            print("Failed to figure alarm time for \(alarm.name)");
            return nil
        }
        return Alarm.Schedule.fixed(dateAndTime)
    }
    
    public class func getSalutation(alarm: AlarmModel) -> LocalizedStringResource {
        if alarm.name == weekDays[6] {
            return "Gut shabbes!"
        } else if weekDays.contains(alarm.name) {
            return "Gut morgn!"
        } else {
            return "Gut yontif!"
        }
    }
}
