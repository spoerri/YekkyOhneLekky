import ActivityKit
import SwiftData
import AlarmKit
import AVFoundation
import Hebcal
import SwiftUI
import CoreLocation
import SunCalc

class AlarmLogic {
    public static nonisolated let Saturday = "Saturday"
    public static nonisolated let Sunday = "Sunday"
    public static nonisolated let Once = "Just once"
    public static nonisolated let RoshChodesh = "Rosh Chodesh"
    public static nonisolated let CholHamoed = "Chol Hamoed"
    public static nonisolated let allDaysOfWeek = Calendar.current.standaloneWeekdaySymbols
    public static let groupLabel: [AlarmType: String] = [.yomTov: "yomim tovim", .explicit: "one offs", .national: "nationals", .fast: "minor fasts"]
    
    public class func getEarliest(_ date: Date?) -> Date? {
        
        //TODO save it, and keep using the old value if we can't get a new one
        guard let date = date else {
            return nil
        }
        let locManager = CLLocationManager()
        locManager.requestWhenInUseAuthorization()
        var currentLocation: CLLocation! = locManager.location
        if locManager.authorizationStatus == .authorizedWhenInUse || locManager.authorizationStatus ==  .authorizedAlways {
            currentLocation = locManager.location
        }
        if currentLocation == nil {
            print("Couldn't get current location")
            return nil
        }
        
        print("latitude",currentLocation.coordinate.latitude,"longitude",currentLocation.coordinate.longitude)

        //kaj starts ~7 minutes before their zman tefilin, which is around an hour before sunrise
        
        //        if let sunrise = SunCalc.getTimes(date: date, latitude: 40.8417, longitude: -73.9394).sunrise {
        if let sunrise = SunCalc.getTimes(date: date, latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude).sunrise {
            return Calendar.current.date(byAdding: .minute, value: -55, to: sunrise)
        } else {
            return nil
        }
    }
    
    private class func getChagim() -> [HEvent] {
        let today = Calendar.current.date(byAdding: .month, value: 0, to:Date())! //verbose to ease testing
        let htoday = HDate(date: today, calendar: .current)
        
        //TODO allow overriding israel
        let il = Locale.current.region == Locale.Region.israel
        
        let holidayTypes = HolidayFlags(arrayLiteral: [ .CHAG, .MINOR_FAST, .MAJOR_FAST, .CHOL_HAMOED, .ROSH_CHODESH ])
        //.MAJOR_FAST instead of just tisha b'av so that we don't have to special yom kipur observed
            
        let holidayFilter: (HEvent) -> Bool = { ((il && !$0.flags.contains(.CHUL_ONLY)) || (!il && !$0.flags.contains(.IL_ONLY)))
            && ((!$0.flags.isDisjoint(with: holidayTypes)  && !$0.flags.contains(.EREV))
                || $0.desc == "Purim" || $0.desc == "Erev Yom Kippur" || $0.desc.contains("Hoshana"))
            }
        
        let thisYears = Hebcal.getAllHolidaysForYear(year: htoday.yy).filter(holidayFilter).filter{ $0.hdate > htoday }
//        print("This year's \(thisYears.map{ $0.hdate.greg() })")
        let hebrewDateNextYear = HDate(yy:htoday.yy+1, mm:htoday.mm, dd:htoday.dd)
        let nextYears = Hebcal.getAllHolidaysForYear(year: htoday.yy+1).filter(holidayFilter).filter{ $0.hdate < hebrewDateNextYear }
//        print("Next year's \(nextYears.map{ $0.hdate.greg() })")
        return thisYears + nextYears
    }
    
    public class func getNextDayOfWeek(_ daysOfWeek: Set<String>, _ hour: Int, _ minute: Int) -> Date? {
        var date = Date()
        let currentHour = Calendar.current.component(.hour, from: date)
        let currentMinute = Calendar.current.component(.minute, from: date)
        if currentHour > hour || (currentHour == hour && currentMinute > minute) {
            date = nextDay(date)
        }
        for _ in 0..<allDaysOfWeek.count {
            if daysOfWeek.contains(allDaysOfWeek[Calendar.current.component(.weekday, from: date)-1]) {
                return date
            }
            date = nextDay(date)
        }
        return nil
    }
    
    private static func nextDay(_ d: Date) -> Date {
        return d+TimeInterval(60*60*24)
    }
    
    //TODO setting on the day of, both before and after the time
    public class func getNextDayToFire(_ alarm: AlarmModel) -> Date? {
        let chagim = getChagim()
        if alarm.alarmType == .explicit {
            return alarm.nextDayToFire == nil ? Date() : alarm.nextDayToFire
        }
        if let weekDay = getNextDayOfWeek(alarm.daysOfWeek, alarm.hour, alarm.minute) {
            return weekDay
        }
        if alarm.alarmType == .saturday {
            return getNextDayOfWeek(Set([Saturday]), alarm.hour, alarm.minute)
        }
        if alarm.alarmType == .national {
            if let legalHoliday = UsHolidays.init(rawValue: alarm.name) {
                let year = Calendar.current.component(.year, from: Date())
                if let thisYears = legalHoliday.date(in: year) {
                    if thisYears > Date() {
                        return thisYears
                    }
                }
                return legalHoliday.date(in: year+1)
            }
        }
        if let chag = chagim.filter({ $0.desc == alarm.name }).first {
            return chag.hdate.greg()
        }
        if alarm.alarmType == .cholHamoed {
            if let chag = chagim.filter({ $0.flags.contains(.CHOL_HAMOED) }).first {
                return chag.hdate.greg()
            }
        }
        if alarm.alarmType == .roshChodesh {
            if let chag = chagim.filter({ $0.flags.contains(.ROSH_CHODESH) }).first {
                return chag.hdate.greg()
            }
        }
        return nil
    }
    
    //TODO should keep track of it instead of niling it out entirely, and restore if the overridingAlarm is disabled (or in the case of one-off, moved)
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
            let dayOfWeek = allDaysOfWeek[Calendar.current.component(.weekday, from: nextDayToFire) - 1]
            if ((dayOfWeek == Saturday && alarm.alarmType > .saturday)
                || (dayOfWeek == Sunday && alarm.alarmType > .national && alarm.alarmType != .weekDay)) {
                alarm.nextDayToFire = nil
            }
        }
    }
    
    public class func schedule(_ alarm: AlarmModel) async {
        do {
            if try isFullyScheduled(alarm) || !alarm.isEnabled {
                return;
            }
            
            alarm.ids.removeAll()
            for _ in 0..<(alarm.repetitions+1) {
                alarm.ids.append(UUID())
                if alarm.duration != nil {
                    alarm.ids.append(UUID()) //for silence
                }
            }
            
            alarm.nextDayToFire = getNextDayToFire(alarm)
            
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
                if let duration = alarm.duration {
                    date.addTimeInterval(duration)
                    try await scheduleAlarm(id: alarm.ids[i+1], date: date, soundConfig: AlertConfiguration.AlertSound.named("silence.mp3"), attributes: attributes)
                    date.addTimeInterval(alarm.repetitionDelay)
                }
            }
        } catch {
            print("\(Date()) Error scheduling alarm: \(error)")
        }
    }
    
    class func isFullyScheduled(_ alarm: AlarmModel) throws -> Bool {
        return try !alarm.ids.isEmpty && Set(alarm.ids).isSubset(of: AlarmManager.shared.alarms.map { $0.id })
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
        if alarm.alarmType == .yomTov {
            return "Gut yontif!"
        } else if alarm.alarmType == .saturday {
            return "Gut shabbes!"
        } else if alarm.alarmType == .cholHamoed {
            return "Gut moed!"
        } else if alarm.alarmType == .roshChodesh {
            return "Gut chodesh!"
        } else {
            return "Gut morgn!"
        }
    }
    
    //TODO refactor - perhaps the view should handle inserting?
    public static func initializeAlarms(modelContext: ModelContext, alarms: [AlarmModel]) async {
        let chagim = AlarmLogic.getChagim()
        print(chagim.map{$0.desc})
        
        await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: CholHamoed, nextDayToFire: chagim.first{ $0.flags.contains(.CHOL_HAMOED)}?.hdate.greg(), alarmType: .cholHamoed)
        await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: RoshChodesh, nextDayToFire: chagim.first{ $0.flags.contains(.ROSH_CHODESH)}?.hdate.greg(), alarmType: .roshChodesh)

        for chag in chagim.filter({ !$0.flags.contains(.CHOL_HAMOED) && !$0.flags.contains(.ROSH_CHODESH) }) {
            await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: chag.desc, nextDayToFire: chag.hdate.greg(), alarmType:
                                    chag.flags.contains(.CHAG) ? .yomTov :
                                    chag.flags.contains(.MINOR_FAST) || chag.desc == "Tish'a B'Av" ? .fast :
                                    .minor)
        }
        
        for national in UsHolidays.allCases {
            await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: national.rawValue, nextDayToFire: nil, alarmType: .national)
        }
        
        //TODO only initialize this if there are no weekdays
        await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: "", nextDayToFire: Date(), alarmType: .weekDay)
        await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: Saturday, nextDayToFire: getNextDayOfWeek(Set([Saturday]), 16, 0), alarmType: .saturday)
        
        await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: Once, nextDayToFire: Date(), alarmType: .explicit)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to initialize: \(error)")
        }
    }
    
    private static func initializeAlarm(modelContext: ModelContext, alarms: [AlarmModel], alarmName: String, nextDayToFire: Date?, alarmType: AlarmType) async {
        if alarmName.isEmpty {
            let existingAlarms = alarms.filter{ !$0.daysOfWeek.isEmpty }
            if (!existingAlarms.isEmpty) {
                for alarm in existingAlarms {
                    await schedule(alarm)
                }
                return
            }
        } else {
            if let alarm = alarms.first(where: { $0.name == alarmName }) {
                await schedule(alarm)
                return
            }
        }
        print("initializing",alarmName)
        let alarm = AlarmModel(
            name: alarmName,
            alarmType: alarmType,
            hour: 8,
            minute: 0,
            nextDayToFire: nextDayToFire,
            isEnabled: false
        )
        if alarmType != .yomTov && alarmType != .saturday {
            alarm.duration = nil
            alarm.repetitions = 0
        }
        //could do individual yomim tovim...
        if alarmType == .national {
            alarm.nextDayToFire = getNextDayToFire(alarm)
            alarm.hour = 7
            alarm.minute = 0
        } else if alarmType == .weekDay {
            alarm.daysOfWeek = Set(allDaysOfWeek).subtracting([Saturday])
            alarm.setNameFromDaysOfWeek()
            alarm.hour = 6
            alarm.minute = 30
        } else if alarmType == .fast || alarmType == .roshChodesh {
            alarm.hour = 6
            alarm.minute = 15
        } else if alarmType == .cholHamoed {
            alarm.hour = 6
            alarm.minute = 30
        } else if alarmType == .minor {
            alarm.hour = 6
            alarm.minute = 0
        }
        if groupLabel.keys.contains(alarmType) && alarmName != Once {
            alarm.isGrouped = true
        }
        modelContext.insert(alarm)
        await schedule(alarm)
    }
}
