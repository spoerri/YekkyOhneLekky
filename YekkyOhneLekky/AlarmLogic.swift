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
    public static let groupLabel: [AlarmType: String] = [.yomTov: "yomim tovim", .explicit: "one offs", .national: "nationals", .fast: "fasts"]
    
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
        
//        print("latitude",currentLocation.coordinate.latitude,"longitude",currentLocation.coordinate.longitude)

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
    
    private class func getNextDayOfWeek(_ daysOfWeek: Set<String>, _ hour: Int, _ minute: Int) throws -> Date {
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
        throw AlarmError.ugh
    }
    
    private static func nextDay(_ d: Date) -> Date {
        return d+TimeInterval(60*60*24)
    }
    
    public class func getNextDayToFire(_ alarm: AlarmModel) throws -> Date {
        if alarm.name == Once {
            return Date()
        }
        if alarm.alarmType == .explicit {
            return alarm.nextDayToFire
        }
        if !alarm.daysOfWeek.isEmpty {
            return try getNextDayOfWeek(alarm.daysOfWeek, alarm.hour, alarm.minute)
        }
        if alarm.alarmType == .saturday {
            return try getNextDayOfWeek(Set([Saturday]), alarm.hour, alarm.minute)
        }
        if alarm.alarmType == .national {
            return try legalHoliday(alarm.name)
        }
        let chagim = getChagim()
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
        throw AlarmError.ugh
    }
    
    private class func legalHoliday(_ name: String) throws -> Date {
        guard let legalHoliday = UsHolidays.init(rawValue: name) else {
            throw AlarmError.ugh
        }
        let year = Calendar.current.component(.year, from: Date())
        let thisYears = try legalHoliday.date(in: year)
        if thisYears > Date() {
            return thisYears
        } else {
            return try legalHoliday.date(in: year+1)
        }
    }
    
    private static func saveOtherAlarmsInGroup(_ editingAlarm: AlarmModel, _ modelContext: ModelContext) async throws {
        if editingAlarm.isGrouped {
            let alarms = Set(try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { $0.isGrouped })))
            for alarm in alarms {
                if alarm.alarmType == editingAlarm.alarmType && alarm.name != editingAlarm.name {
                    alarm.copyConfigFrom(editingAlarm)
                    if alarm.alarmType != .explicit {
                        alarm.hour = editingAlarm.hour
                        alarm.minute = editingAlarm.minute
                        alarm.isEnabled = editingAlarm.isEnabled
                    }
                    await schedule(alarm)
                }
            }
        }
    }
    
    private static func saveEditingAlarm(_ editingAlarm: AlarmModel, _ modelContext: ModelContext) async throws {
        if editingAlarm.name != AlarmLogic.Once && editingAlarm.alarmType == AlarmType.explicit {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let alarmName = dateFormatter.string(from: editingAlarm.nextDayToFire)
            if alarmName != editingAlarm.name {
                if let sameNamed = try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { $0.name == alarmName})).first {
                    try sameNamed.unschedule()
                    editingAlarm.modelContext?.delete(sameNamed)
                }
                editingAlarm.name = alarmName
            }
        }
        await schedule(editingAlarm)
    }
    
    public class func saveAlarm(_ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>, _ originalDayToFire: Date?) async throws {
        guard editingAlarm.modelContext != nil else { throw AlarmError.ugh }
        let modelContext = editingAlarm.modelContext!
        
        printScheduledAlarms()
        
        if editingAlarm.alarmType == .weekDay {
            try await saveWeekDayAlarms(editingAlarm, originalDaysOfWeek, modelContext)
        } else if editingAlarm.name == AlarmLogic.Once && editingAlarm.isEnabled {
            await saveNewOneOffAlarm(editingAlarm, modelContext)
        } else {
            try await saveOtherAlarmsInGroup(editingAlarm, modelContext)
            try await saveEditingAlarm(editingAlarm, modelContext)
        }
        
        if let originalDayToFire = originalDayToFire {
            try await unoverride(editingAlarm.modelContext, originalDayToFire)
        }
        
        try modelContext.save()
    }
    
    private class func disablePastOneOffs(_ modelContext: ModelContext?) throws {
        let endOfToday = Calendar.current.startOfDay(for: Date()) + TimeInterval(60*60*24)
        if let todays = try modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in other.isEnabled && other.nextDayToFire <= endOfToday})) {
            for alarm in todays {
                if alarm.nextDayToFire < Date() && alarm.alarmType == .explicit {
                    alarm.isEnabled = false
                }
            }
        }
    }
    
    private static func saveWeekDayAlarms(_ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>, _ modelContext: ModelContext) async throws {
        if editingAlarm.daysOfWeek.isEmpty {
            editingAlarm.daysOfWeek = originalDaysOfWeek
            throw AlarmError.ugh
        }
        let removedDays = originalDaysOfWeek.subtracting(editingAlarm.daysOfWeek)
        if !removedDays.isEmpty {
            let newAlarm = AlarmModel(
                name: AlarmModel.nameFromDaysOfWeek(removedDays),
                alarmType: .weekDay,
                daysOfWeek: removedDays,
                hour: editingAlarm.hour,
                minute: editingAlarm.minute,
                nextDayToFire: Date.distantFuture
            )
            newAlarm.nextDayToFire = try getNextDayToFire(newAlarm)
            newAlarm.copyConfigFrom(editingAlarm)
            newAlarm.isEnabled = false
            modelContext.insert(newAlarm)
        }
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { $0.isWeekDay })) {
            if !editingAlarm.daysOfWeek.isDisjoint(with: alarm.daysOfWeek) && alarm != editingAlarm {
                alarm.daysOfWeek.subtract(editingAlarm.daysOfWeek)
                if alarm.daysOfWeek.isEmpty {
                    print("dayOfWeek alarm left empty, deleting")
                    try alarm.unschedule()
                    modelContext.delete(alarm)
                } else {
                    alarm.name = AlarmModel.nameFromDaysOfWeek(alarm.daysOfWeek)
                    await schedule(alarm)
                }
            }
        }
        editingAlarm.name = AlarmModel.nameFromDaysOfWeek(editingAlarm.daysOfWeek)
        await schedule(editingAlarm)
    }
    
    private static func saveNewOneOffAlarm(_ editingAlarm: AlarmModel, _ modelContext: ModelContext) async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let newAlarm = AlarmModel(
            name: dateFormatter.string(from: editingAlarm.nextDayToFire),
            alarmType: AlarmType.explicit,
            hour: editingAlarm.hour,
            minute: editingAlarm.minute,
            nextDayToFire: editingAlarm.nextDayToFire
        )
        newAlarm.copyConfigFrom(editingAlarm)
        modelContext.insert(newAlarm)
        editingAlarm.isGrouped = false
        editingAlarm.isEnabled = false
        await schedule(newAlarm)
    }
    
    private class func unoverride(_ modelContext: ModelContext?, _ date: Date) async throws {
        let start = Calendar.current.startOfDay(for: date)
        let stop = start + TimeInterval(60*60*24)
        if let overriddenAlarm = try modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in start <= other.nextDayToFire && other.nextDayToFire < stop && other.isOverridden })).sorted(using: SortDescriptor(\.alarmType)).first {
            overriddenAlarm.isOverridden = false
            await schedule(overriddenAlarm)
        }
    }
    
    private class func overrideAsAppropriate(_ alarm: AlarmModel) throws {
        if alarm.isOverridden && Calendar.current.startOfDay(for: alarm.nextDayToFire) == Calendar.current.startOfDay(for: Date()) {
            return
        }
        
        alarm.isOverridden = false
        
        let alarmName = alarm.name
        let start = Calendar.current.startOfDay(for: alarm.nextDayToFire)
        let stop = start+TimeInterval(60*60*24)
        
        if let sameDayAlarms = try alarm.modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in
            start <= other.nextDayToFire && other.nextDayToFire < stop &&
            other.name != alarmName && !other.isOverridden && other.name != Once})) {
            for other in sameDayAlarms {
                if other.alarmType > alarm.alarmType {
                    try other.unschedule()
                    other.isOverridden = true
                } else if other.isEnabled {
                    if !alarm.isWeekDay { //TOOD is this fine?
                        alarm.isOverridden = true
                    }
                }
            }
        }
        //if this alarm falls on a saturday or sunday which hasn't been scheduled yet, and is lower priority, and if the saturday/sunday alarm is enabled then override this alarm
        let dayOfWeek = allDaysOfWeek[Calendar.current.component(.weekday, from: alarm.nextDayToFire) - 1]
        if dayOfWeek == Saturday && alarm.alarmType > .saturday {
            try alarm.modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { other in
                other.isEnabled && other.isShabbos })).forEach { _ in
                alarm.isOverridden = true
            }
        } else if dayOfWeek == Sunday && alarm.alarmType > .national && alarm.alarmType != .weekDay {
            try alarm.modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { other in
                other.isEnabled && other.isWeekDay })).forEach { other in
                    if other.daysOfWeek.contains(dayOfWeek) {
                        alarm.isOverridden = true
                    }
                }
        }
        
        //TODO what about the converse? enabling/disabling a weekday alarm, override/unoverride any existing same day alarms for those days?
    }
    
    public class func reschedule(_ alarm: AlarmModel) async throws {
        if try isFullyScheduled(alarm) {
            return;
        }
        try disablePastOneOffs(alarm.modelContext) //to avoid previous alarm today from overriding
        await schedule(alarm)
    }
    
    //TODO pull the AlarmKit stuff out to make unit testing easier
    private class func schedule(_ alarm: AlarmModel) async {
        print("Perhaps scheduling", alarm.name, ":", alarm.nextDayToFire)
        do {
            try alarm.unschedule()
            
            if !alarm.isEnabled {
                return;
            }
            
            for _ in 0..<(alarm.repetitions+1) {
                alarm.ids.append(UUID())
                if alarm.duration != nil {
                    alarm.ids.append(UUID()) //for silence
                }
            }
            
            alarm.nextDayToFire = try getNextDayToFire(alarm)
            
            try overrideAsAppropriate(alarm)
            if alarm.isOverridden {
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
//            print("Using sound: \(soundConfig)")
            
            var date = try alarm.getAlarmDateAndTime()
            
            if date < Date() {
                return
            }
            
            for i in 0...alarm.repetitions {
                try await scheduleAlarm(id: alarm.ids[i*2], date: date, soundConfig: soundConfig, attributes: attributes)
                if let duration = alarm.duration {
                    date.addTimeInterval(duration)
                    try await scheduleAlarm(id: alarm.ids[i*2+1], date: date, soundConfig: AlertConfiguration.AlertSound.named("silence.mp3"), attributes: attributes)
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
        print("\(Date()): Scheduling \(id) for \(date)")
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
    
    //TODO refactor - maybe the view should handle inserting?
    public static func initializeAlarms(modelContext: ModelContext, alarms: [AlarmModel]) async throws {
        printScheduledAlarms()
        print("stopping them all :)")
        try AlarmManager.shared.alarms.forEach{ try AlarmManager.shared.stop(id: $0.id )}
        
        let chagim = getChagim()
        print("Chagim",chagim.map{$0.desc})
        
        try await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: CholHamoed, nextDayToFire: chagim.first{ $0.flags.contains(.CHOL_HAMOED)}!.hdate.greg(), alarmType: .cholHamoed)
        try await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: RoshChodesh, nextDayToFire: chagim.first{ $0.flags.contains(.ROSH_CHODESH)}!.hdate.greg(), alarmType: .roshChodesh)

        for chag in chagim.filter({ !$0.flags.contains(.CHOL_HAMOED) && !$0.flags.contains(.ROSH_CHODESH) }) {
            try await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: chag.desc, nextDayToFire: chag.hdate.greg(), alarmType:
                                    chag.flags.contains(.CHAG) ? .yomTov :
                                    chag.flags.contains(.MINOR_FAST) || chag.desc == "Tish'a B'Av" ? .fast :
                                    .minor)
        }
        
        for national in UsHolidays.allCases {
            try await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: national.rawValue, nextDayToFire: legalHoliday(national.rawValue), alarmType: .national)
        }
        
        try await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: "", nextDayToFire: Date(), alarmType: .weekDay)
        try await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: Saturday, nextDayToFire: getNextDayOfWeek(Set([Saturday]), 16, 0), alarmType: .saturday)
        
        try await initializeAlarm(modelContext: modelContext, alarms: alarms, alarmName: Once, nextDayToFire: Date(), alarmType: .explicit)
        
        for alarm in alarms.filter({$0.nextDayToFire < Date() && $0.isExplicit && $0.name != AlarmLogic.Once}) {
            modelContext.delete(alarm)
        }
        
        printScheduledAlarms()
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to initialize: \(error)")
        }
    }
    
    private static func printScheduledAlarms() {
        do {
            print("All scheduled alarms:\n"+(try AlarmManager.shared.alarms.map { $0.schedule.debugDescription }.joined(separator: "\n")))
        } catch {
            print("Couldn't print scheduled alarms", error)
        }
    }
    
    private static func initializeAlarm(modelContext: ModelContext, alarms: [AlarmModel], alarmName: String, nextDayToFire: Date, alarmType: AlarmType) async throws {
        if alarmType == .weekDay {
            let existingAlarms = alarms.filter{ $0.isWeekDay }
            if (!existingAlarms.isEmpty) {
                for alarm in existingAlarms {
                    try await reschedule(alarm)
                }
                return
            }
        } else if alarmType == .explicit {
            let existingAlarms = alarms.filter{ $0.isExplicit }
            if (!existingAlarms.isEmpty) {
                for alarm in existingAlarms {
                    try await reschedule(alarm)
                }
                return
            }
        } else {
            if let alarm = alarms.first(where: { $0.name == alarmName }) {
                try await reschedule(alarm)
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
            alarm.hour = 7
            alarm.minute = 0
        } else if alarmType == .weekDay {
            alarm.daysOfWeek = Set(allDaysOfWeek).subtracting([Saturday])
            alarm.name = AlarmModel.nameFromDaysOfWeek(alarm.daysOfWeek)
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
    }
}
