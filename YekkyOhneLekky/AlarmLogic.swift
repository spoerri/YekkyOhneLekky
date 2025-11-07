import ActivityKit
import SwiftData
import AlarmKit
import AVFoundation
import Hebcal
import SwiftUI

class AlarmLogic {
    public static nonisolated let Once = "Just once"
    public static nonisolated let allDaysOfWeek = Calendar.current.standaloneWeekdaySymbols
    
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
        
        return [HEvent.init(hdate: htoday, desc: Once)] + thisYears + nextYears + allDaysOfWeek.compactMap {
            if let nextDate = getNextDayOfWeek(nameOfDay: $0) {
                HEvent.init(hdate: HDate(date: nextDate, calendar: .current), desc: $0) //TODO good syntax?
            } else {
                nil
            }
        }
    }
    
    private class func getNextDayOfWeek(nameOfDay: String) -> Date? {
        for (index, name) in allDaysOfWeek.enumerated() {
            if nameOfDay == name {
                return Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: index+1), matchingPolicy: .nextTimePreservingSmallerComponents)
            }
        }
        return nil
    }
    
    public class func getNextDayToFire(_ alarm: AlarmModel) throws -> Date? {
        if alarm.alarmType == AlarmModel.explicit {
            return Date()
        }
        if let weekDay = getNextDayOfWeek(nameOfDay: alarm.name) {
            return weekDay
        }
        if let chag = getChagim().filter({ $0.desc == alarm.name }).first {
            return chag.hdate.greg()
        } else {
            return nil
        }
    }
    
    private class func overrideAsAppropriate(_ alarm: AlarmModel) throws {
        if let nextDayToFire = alarm.nextDayToFire {
            let alarmName = alarm.name
            if let sameDayAlarms = try alarm.modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { other in
                nextDayToFire == other.nextDayToFire && alarmName != other.name && other.isEnabled })) {
                if let sameDayAlarm = sameDayAlarms.first {
                    if sameDayAlarm.alarmType > alarm.alarmType {
                        sameDayAlarm.unschedule()
                    } else {
                        alarm.nextDayToFire = nil
                    }
                }
            }
        }
    }
    
    public class func schedule(_ alarm: AlarmModel) async {
        do {
            if alarm.ids.count != (alarm.repetitions+1)*2 {
                alarm.ids.removeAll()
                for _ in 0..<(alarm.repetitions+1) {
                    alarm.ids.append(UUID())
                    alarm.ids.append(UUID()) //for silence
                }
            }
            
            if try isFullyScheduled(alarm) || !alarm.isEnabled {
                return;
            }
            
            try alarm.nextDayToFire = getNextDayToFire(alarm)
            
            try overrideAsAppropriate(alarm)
            
            
            if alarm.nextDayToFire == nil {
                return
            }
            
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
            
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: EmptyMetadata(),
                tintColor: .black
            )
            
            let soundConfig: AlertConfiguration.AlertSound
            if let selectedSoundName = alarm.selectedSound {
                // Verify the sound file exists
                if let _ = Bundle.main.url(forResource: selectedSoundName, withExtension: "mp3") {
                    soundConfig = AlertConfiguration.AlertSound.named(selectedSoundName+".mp3")
                } else {
                    soundConfig = .default
                    print("Custom sound \(selectedSoundName).mp3 not found in bundle, using default")
                }
            } else {
                soundConfig = .default
            }
            
            print("Using sound: \(soundConfig)")
            
            guard var date = alarm.getAlarmDate() else {
                throw AlarmError.ugh
            }
            
            if date < Date() {
                return
            }
            
            for i in 0...alarm.repetitions {
                try await scheduleAlarm(id: alarm.ids[i], date: date, soundConfig: soundConfig, attributes: attributes)
                date.addTimeInterval(alarm.duration)
                try await scheduleAlarm(id: alarm.ids[i+1], date: date, soundConfig: AlertConfiguration.AlertSound.named("silence.mp3"), attributes: attributes)
                date.addTimeInterval(alarm.repetitionDelay)
            }
        } catch {
            print("\(Date()) Error scheduling alarm: \(error)")
        }
    }
    
    class func isFullyScheduled(_ alarm: AlarmModel) throws -> Bool {
        return try Set(alarm.ids).isSubset(of: AlarmManager.shared.alarms.map { $0.id })
    }
    
    struct EmptyMetadata : AlarmMetadata {
    }
    
    private class func scheduleAlarm(id: UUID, date: Date, soundConfig: AlertConfiguration.AlertSound, attributes: AlarmAttributes<EmptyMetadata>) async throws {
        if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
            return
        }
        let alarmConfiguration = AlarmManager.AlarmConfiguration<EmptyMetadata>(
            schedule: Alarm.Schedule.fixed(date),
            attributes: attributes,
            stopIntent: ScheduleNextAlarmsIntent(alarmID: id.uuidString),
            sound: soundConfig
        )
//            print("\(Date()) Scheduling alarm with ID: \(alarm.id) for \(schedule)")
        print("\(Date()) Scheduling for \(date)")
        _ = try await AlarmManager.shared.schedule(id: id, configuration: alarmConfiguration)
    }
    
    public class func getSalutation(alarm: AlarmModel) -> LocalizedStringResource {
        if alarm.name == allDaysOfWeek[6] {
            return "Gut shabbes!"
        } else if alarm.alarmType == AlarmModel.dayOfWeek {
            return "Gut morgn!"
        } else {
            return "Gut yontif!"
        }
    }
    
    public static func initializeAlarms(modelContext: ModelContext, alarms: [AlarmModel]) async {
        let chagim = AlarmLogic.getChagim()
        print(chagim.map(\.desc))
        //TODO also delete any alarms not in chagim, for when user goes to israel
        for chag in chagim {
            let alarm = initializeAlarm(modelContext: modelContext, alarms: alarms, hEvent: chag)
            await schedule(alarm)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to initialize: \(error)")
        }
    }
    
    private static func initializeAlarm(modelContext: ModelContext, alarms: [AlarmModel], hEvent: HEvent) -> AlarmModel {
        if let alarm = alarms.first(where: { $0.name == hEvent.desc }) {
            alarm.nextDayToFire = hEvent.hdate.greg()
            return alarm
        }
        let alarm = AlarmModel(
            name: hEvent.desc,
            hour: 8,
            minute: 0,
            nextDayToFire: hEvent.hdate.greg()
        )
        if alarm.name == Once || (alarm.alarmType == AlarmModel.dayOfWeek && alarm.name != "Saturday") { //TODO cleaner way of checking
            alarm.repetitions = 0
        }
        alarm.isEnabled = false
        modelContext.insert(alarm)
        return alarm
    }
}
