import ActivityKit
import SwiftData
import AlarmKit
import AVFoundation
import Hebcal
import SwiftUI
import CoreLocation
import SunCalc
import OSLog

class AlarmLogic {
    public static nonisolated let Saturday = "Saturday"
    public static nonisolated let SaturdayErevPesach = "Saturday Erev Pesach"
    public static nonisolated let Sunday = "Sunday"
    public static nonisolated let Once = "Just once" //TODO make a separate alarm type to avoid forgetting to check
    public static nonisolated let RoshChodesh = "Rosh Chodesh"
    public static nonisolated let CholHamoed = "Chol Hamoed"
    public static nonisolated let allDaysOfWeek = Calendar.current.standaloneWeekdaySymbols
    public static let groupLabel: [AlarmType: String] = [.yomTov: "yomim tovim", .explicit: "one offs", .national: "nationals", .fast: "fasts", .specialSaturday: "special shabboses"]
    
    public class func getEarliest(_ now: Date, _ date: Date?) -> Date? {
        
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
            Logger.shared.info("Couldn't get current location")
            return nil
        }
        
//        Logger.shared.info("latitude",currentLocation.coordinate.latitude,"longitude",currentLocation.coordinate.longitude)

        //kaj starts ~7 minutes before their zman tefilin, which is around an hour before sunrise
        
        //        if let sunrise = SunCalc.getTimes(date: date, latitude: 40.8417, longitude: -73.9394).sunrise {
        if let sunrise = SunCalc.getTimes(date: date, latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude).sunrise {
            return Calendar.current.date(byAdding: .minute, value: -55, to: sunrise)
        } else {
            return nil
        }
    }
    
    private class func getChagim(_ now: Date) -> [HEvent] {
        let htoday = HDate(date: Calendar.current.date(byAdding: .month, value: 0, to: now)!, calendar: .current)
        
        //TODO allow manually overriding this
        let il = Locale.current.region == Locale.Region.israel
        
        let holidayTypes = HolidayFlags(arrayLiteral: [ .CHAG, .MINOR_FAST, .CHOL_HAMOED, .ROSH_CHODESH, .SPECIAL_SHABBAT ])
            
        let holidayFilter: (HEvent) -> Bool = { ((il && !$0.flags.contains(.CHUL_ONLY)) || (!il && !$0.flags.contains(.IL_ONLY)))
            && (!$0.flags.isDisjoint(with: holidayTypes)
                || $0.desc == "Purim" || $0.desc.contains("Yom Kippur") || $0.desc.contains("Hoshana") || ($0.desc.starts(with:"Chanuka") && !$0.flags.contains(.EREV)))
            }
        
        let thisYears = Hebcal.getAllHolidaysForYear(year: htoday.yy).filter(holidayFilter).filter{ $0.hdate > htoday }
//        Logger.shared.info("This year's \(thisYears.map{ $0.hdate.greg() })")
        let thisYearsHolidayNames = thisYears.map({ $0.desc })
        let nextYears = Hebcal.getAllHolidaysForYear(year: htoday.yy+1).filter(holidayFilter).filter{ !thisYearsHolidayNames.contains($0.desc) }
//        Logger.shared.info("Next year's \(nextYears.map{ $0.hdate.greg() })")
        var all = thisYears + nextYears
        
        all.removeAll(where: {
            $0.flags.contains(.SPECIAL_SHABBAT) && !["Shabbat HaChodesh", "Shabbat Shekalim", "Shabbat HaGadol"].contains($0.desc)
        })
        
        addVayakehlPekudei(&all, htoday.yy)
        addVayakehlPekudei(&all, htoday.yy+1)
        addForShabbosErevPesach(&all, htoday.yy)
        addForShabbosErevPesach(&all, htoday.yy+1)
        addForShabbosErevSheviiShelPesach(&all, htoday.yy)
        addForShabbosErevSheviiShelPesach(&all, htoday.yy+1)
        addForShabbosChanukah(&all, htoday.yy)
        addForShabbosChanukah(&all, htoday.yy+1)
        
        return all
    }
    
    private static func addVayakehlPekudei(_ all: inout [HEvent], _ year: Int) {
        if let vayakehlPekudei = Sedra(year: year, il: false).find(-26) { //dumb api
            all.append(HEvent(hdate: vayakehlPekudei, desc: "Vayakhel Pekudei", flags: .SPECIAL_SHABBAT))
        }
    }
    
    private static func addForShabbosErevPesach(_ all: inout [HEvent], _ year: Int) {
        let shabbosErevPesach = all.filter({ $0.desc == "Erev Pesach" && $0.hdate.dow() == .SAT})
        for s in shabbosErevPesach {
            all.removeAll(where: { $0.hdate == s.hdate }) //to replace it with the following:
            //TODO this should appear the first time it happens, but not disappear when not relevant. is there a significantly better way?
            all.append(HEvent(hdate: s.hdate, desc: SaturdayErevPesach, flags: .SPECIAL_SHABBAT))
            all.append(HEvent(hdate: HDate(absdate: s.hdate.abs() - 7), desc: "Shabbat HaGadol", flags: .SPECIAL_SHABBAT))
        }
    }
    
    private static func addForShabbosErevSheviiShelPesach(_ all: inout [HEvent], _ year: Int) {
        let shabbosErevSheviiShelPesach = all.filter({ $0.desc == "Pesach VI (CH''M)" && $0.hdate.dow() == .SAT})
        for s in shabbosErevSheviiShelPesach {
            all.removeAll(where: { $0.hdate == s.hdate }) //to replace it with the following:
            all.append(HEvent(hdate: s.hdate, desc: "Saturday Erev Shevii Shel Pesach", flags: .SPECIAL_SHABBAT))
        }
    }
    
    private static func addForShabbosChanukah(_ all: inout [HEvent], _ year: Int) {
        var n = 1
        for s in all.filter({ $0.desc.starts(with:"Chanuka") && $0.hdate.dow() == .SAT}) {
            all.append(HEvent(hdate: s.hdate, desc: "Shabbat Chanukah \(n)", flags: .SPECIAL_SHABBAT))
            n+=1
        }
        all.removeAll(where: { $0.desc.starts(with:"Chanuka") })
    }
    
    private class func getNextDayOfWeek(_ now: Date, _ daysOfWeek: Set<String>, _ hour: Int, _ minute: Int) throws -> Date {
        var date = now
        let currentHour = Calendar.current.component(.hour, from: date)
        let currentMinute = Calendar.current.component(.minute, from: date)
        if currentHour > hour || (currentHour == hour && currentMinute >= minute) {
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
    
    //TODO support saving an alarm all night for the coming day, with code like currentMinute check above
    //TODO check that getChagim does indeed start with tomorrow
    private static func tomorrow(_ now: Date) -> Date {
        return nextDay(now)
    }
    
    private static func nextDay(_ d: Date) -> Date {
        return d+TimeInterval(60*60*24)
    }
    
    public class func getNextDayToFire(_ now: Date, _ alarm: AlarmModel) throws -> Date {
        if alarm.name == Once {
            return now
        }
        if alarm.alarmType == .explicit {
            return alarm.nextDayToFire
        }
        if !alarm.daysOfWeek.isEmpty {
            return try getNextDayOfWeek(now, alarm.daysOfWeek, alarm.hour, alarm.minute)
        }
        if alarm.alarmType == .saturday {
            return try getNextDayOfWeek(now, Set([Saturday]), alarm.hour, alarm.minute)
        }
        if alarm.alarmType == .national {
            return try legalHoliday(now, alarm.name)
        }
        let chagim = getChagim(now)
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
    
    private class func legalHoliday(_ now:Date, _ name: String) throws -> Date {
        guard let legalHoliday = UsHolidays.init(rawValue: name) else {
            throw AlarmError.ugh
        }
        let year = Calendar.current.component(.year, from: tomorrow(now))
        let thisYears = try legalHoliday.date(in: year)
        if thisYears > now {
            return thisYears
        } else {
            return try legalHoliday.date(in: year+1)
        }
    }
    
    private static func saveOtherAlarmsInGroup(_ now: Date, _ editingAlarm: AlarmModel, _ modelContext: ModelContext) async throws {
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
                    await schedule(now, alarm)
                }
            }
        }
    }
    
    private static func saveEditingAlarm(_ now: Date, _ editingAlarm: AlarmModel, _ modelContext: ModelContext) async throws {
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
        await schedule(now, editingAlarm)
    }
    
    public class func saveAlarm(_ now: Date, _ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>, _ originalDayToFire: Date?) async throws {
        guard editingAlarm.modelContext != nil else { throw AlarmError.ugh }
        let modelContext = editingAlarm.modelContext!
        
        printScheduledAlarms()
        
        if editingAlarm.alarmType == .weekDay {
            try await saveWeekDayAlarms(now, editingAlarm, originalDaysOfWeek, modelContext)
        } else if editingAlarm.name == AlarmLogic.Once && editingAlarm.isEnabled {
            await saveNewOneOffAlarm(now, editingAlarm, modelContext)
        } else {
            try await saveOtherAlarmsInGroup(now, editingAlarm, modelContext)
            try await saveEditingAlarm(now, editingAlarm, modelContext)
        }
        
        if let originalDayToFire = originalDayToFire {
            try await unoverride(now, editingAlarm.modelContext, originalDayToFire)
        }
        
        try modelContext.save()
    }
    
    private class func disablePastOneOffs(_ now: Date, _ modelContext: ModelContext?) throws {
        let endOfToday = Calendar.current.startOfDay(for: now) + TimeInterval(60*60*24)
        if let todays = try modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in other.isEnabled && other.nextDayToFire <= endOfToday})) {
            for alarm in todays {
                if alarm.nextDayToFire < now && alarm.alarmType == .explicit && alarm.name != AlarmLogic.Once {
                    alarm.isEnabled = false
                }
            }
        }
    }
    
    private static func saveWeekDayAlarms(_ now:Date, _ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>, _ modelContext: ModelContext) async throws {
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
                maybeDayToFire: Date.distantFuture,
                nextDayToFire: Date.distantFuture
            )
            newAlarm.maybeDayToFire = try getNextDayToFire(now, newAlarm)
            newAlarm.nextDayToFire = newAlarm.maybeDayToFire
            newAlarm.copyConfigFrom(editingAlarm)
            newAlarm.isEnabled = false
            modelContext.insert(newAlarm)
        }
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { $0.isWeekDay })) {
            if !editingAlarm.daysOfWeek.isDisjoint(with: alarm.daysOfWeek) && alarm != editingAlarm {
                alarm.daysOfWeek.subtract(editingAlarm.daysOfWeek)
                if alarm.daysOfWeek.isEmpty {
                    Logger.shared.info("dayOfWeek alarm left empty, deleting")
                    try alarm.unschedule()
                    modelContext.delete(alarm)
                } else {
                    alarm.name = AlarmModel.nameFromDaysOfWeek(alarm.daysOfWeek)
                    await schedule(now, alarm)
                }
            }
        }
        editingAlarm.name = AlarmModel.nameFromDaysOfWeek(editingAlarm.daysOfWeek)
        await schedule(now, editingAlarm)
    }
    
    private static func saveNewOneOffAlarm(_ now: Date, _ editingAlarm: AlarmModel, _ modelContext: ModelContext) async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let newAlarm = AlarmModel(
            name: dateFormatter.string(from: editingAlarm.nextDayToFire),
            alarmType: AlarmType.explicit,
            hour: editingAlarm.hour,
            minute: editingAlarm.minute,
            maybeDayToFire: editingAlarm.maybeDayToFire,
            nextDayToFire: editingAlarm.nextDayToFire
        )
        newAlarm.copyConfigFrom(editingAlarm)
        modelContext.insert(newAlarm)
        editingAlarm.isGrouped = false
        editingAlarm.isEnabled = false
        await schedule(now, newAlarm)
    }
    
    private class func unoverride(_ now: Date, _ modelContext: ModelContext?, _ date: Date) async throws {
        let start = Calendar.current.startOfDay(for: date)
        let stop = start + TimeInterval(60*60*24)
        if let overriddenAlarm = try modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in start <= other.nextDayToFire && other.nextDayToFire < stop && other.isOverridden })).sorted(using: SortDescriptor(\.alarmType)).first {
            overriddenAlarm.isOverridden = false
            await schedule(now, overriddenAlarm)
        }
    }
    
    private class func overrideAsAppropriate(_ now: Date, _ alarm: AlarmModel) throws {
        if alarm.isOverridden && Calendar.current.startOfDay(for: alarm.nextDayToFire) == Calendar.current.startOfDay(for: now) {
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
                    alarm.isOverridden = true
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
    
    public class func reschedule(_ now: Date, _ alarm: AlarmModel) async throws {
        if try isFullyScheduled(alarm) {
            return;
        }
        Logger.shared.notice("not fully scheduled")
        try disablePastOneOffs(now, alarm.modelContext) //to avoid previous alarm today from overriding
        await schedule(now, alarm)
    }
    
    //TODO pull the AlarmKit stuff out to make unit testing easier
    private class func schedule(_ now: Date, _ alarm: AlarmModel) async {
        Logger.shared.notice("Perhaps scheduling \(alarm.name, privacy: .public): \(alarm.nextDayToFire, privacy: .public)")
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
            
            alarm.maybeDayToFire = try getNextDayToFire(now, alarm)
            alarm.nextDayToFire = alarm.maybeDayToFire
            
            try overrideAsAppropriate(now, alarm)
            if alarm.isOverridden {
                return
            }
            
            Logger.shared.notice("not overridden")
            
            let alertPresentation = AlarmPresentation.Alert(
                title: getSalutation(alarm: alarm),
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
                    Logger.shared.info("Custom sound \(selectedSoundName).mp3 not found in bundle, using default")
                }
            } else {
                soundConfig = .default
            }
//            Logger.shared.info("Using sound: \(soundConfig)")
            
            var date = try alarm.getAlarmDateAndTime(now)
            
            if date < now {
                return
            }
            
            Logger.shared.notice("not in the past") //TODO debug
            
            for i in 0...alarm.repetitions {
                try await scheduleAlarm(now, id: alarm.ids[i*2], date: date, soundConfig: soundConfig, attributes: attributes)
                if let duration = alarm.duration {
                    date.addTimeInterval(duration)
                    try await scheduleAlarm(now, id: alarm.ids[i*2+1], date: date, soundConfig: AlertConfiguration.AlertSound.named("silence.mp3"), attributes: attributes)
                    date.addTimeInterval(alarm.repetitionDelay)
                }
            }
        } catch {
            Logger.shared.info("\(now) Error scheduling alarm: \(error)")
        }
    }
    
    class func isFullyScheduled(_ alarm: AlarmModel) throws -> Bool {
        return try !alarm.ids.isEmpty && Set(alarm.ids).isSubset(of: AlarmManager.shared.alarms.map { $0.id })
    }
    
    struct EmptyMetadata : AlarmMetadata {
    }
    
    private class func scheduleAlarm(_ now: Date, id: UUID, date: Date, soundConfig: AlertConfiguration.AlertSound, attributes: AlarmAttributes<EmptyMetadata>) async throws {
        if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
            return
        }
        let alarmConfiguration = AlarmManager.AlarmConfiguration<EmptyMetadata>(
            schedule: Alarm.Schedule.fixed(date),
            attributes: attributes,
            stopIntent: ScheduleNextAlarmsIntent(alarmID: id.uuidString),
            sound: soundConfig
        )
        Logger.shared.notice("Scheduling \(id, privacy: .public) for \(date, privacy: .public)")
        _ = try await AlarmManager.shared.schedule(id: id, configuration: alarmConfiguration)
    }
    
    private class func getSalutation(alarm: AlarmModel) -> LocalizedStringResource {
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
    //TODO maybe hard code the list
    public static func initializeAlarms(_ now: Date, modelContext: ModelContext, alarms: [AlarmModel]) async throws {
        printScheduledAlarms()
        Logger.shared.info("stopping them all :)")
        try AlarmManager.shared.alarms.forEach{ try AlarmManager.shared.stop(id: $0.id )}
        
        let chagim = getChagim(now)
        let chagimDescription = chagim.map{$0.desc}
        Logger.shared.info("Chagim \(chagimDescription)")
        
        try await initializeAlarm(now, modelContext: modelContext, alarms: alarms, alarmName: CholHamoed, nextDayToFire: chagim.first{ $0.flags.contains(.CHOL_HAMOED)}!.hdate.greg(), alarmType: .cholHamoed)
        try await initializeAlarm(now, modelContext: modelContext, alarms: alarms, alarmName: RoshChodesh, nextDayToFire: chagim.first{ $0.flags.contains(.ROSH_CHODESH)}!.hdate.greg(), alarmType: .roshChodesh)

        for chag in chagim.filter({ $0.flags.isDisjoint(with: [.CHOL_HAMOED, .ROSH_CHODESH, .SPECIAL_SHABBAT]) }) {
            try await initializeAlarm(now, modelContext: modelContext, alarms: alarms, alarmName: chag.desc, nextDayToFire: chag.hdate.greg(), alarmType:
                                    chag.flags.contains(.CHAG) ? .yomTov :
                                    chag.flags.contains(.MINOR_FAST) || chag.desc == "Tish'a B'Av" ? .fast :
                                    .minor)
        }
        
        for chag in chagim.filter({ $0.flags.contains(.SPECIAL_SHABBAT)}) {
            try await initializeAlarm(now, modelContext: modelContext, alarms: alarms, alarmName: chag.desc, nextDayToFire: chag.hdate.greg(), alarmType: .specialSaturday)
        }
        
        for national in UsHolidays.allCases {
            try await initializeAlarm(now, modelContext: modelContext, alarms: alarms, alarmName: national.rawValue, nextDayToFire: legalHoliday(now, national.rawValue), alarmType: .national)
        }
        
        try await initializeAlarm(now, modelContext: modelContext, alarms: alarms, alarmName: "", nextDayToFire: now, alarmType: .weekDay)
        try await initializeAlarm(now, modelContext: modelContext, alarms: alarms, alarmName: Saturday, nextDayToFire: getNextDayOfWeek(now, Set([Saturday]), 16, 0), alarmType: .saturday)
        
        try await initializeAlarm(now, modelContext: modelContext, alarms: alarms, alarmName: Once, nextDayToFire: now, alarmType: .explicit)
        
        for alarm in alarms.filter({$0.nextDayToFire < now && $0.isExplicit && $0.name != AlarmLogic.Once}) {
            modelContext.delete(alarm)
        }
        
        printScheduledAlarms()
        
        do {
            try modelContext.save()
        } catch {
            Logger.shared.info("Failed to initialize: \(error)")
        }
    }
    
    public static nonisolated func printScheduledAlarms() {
        do {
            let descriptions = try AlarmManager.shared.alarms.map { $0.schedule.debugDescription }.joined(separator: "\n")
            Logger.shared.notice("All scheduled alarms:\n\(descriptions, privacy: .public)")
        } catch {
            Logger.shared.info("Couldn't print scheduled alarms: \(error)")
        }
    }
    
    private static func initializeAlarm(_ now:Date, modelContext: ModelContext, alarms: [AlarmModel], alarmName: String, nextDayToFire: Date, alarmType: AlarmType) async throws {
        if alarmType == .weekDay {
            let existingAlarms = alarms.filter{ $0.isWeekDay }
            if (!existingAlarms.isEmpty) {
                for alarm in existingAlarms {
                    try await reschedule(now, alarm)
                }
                return
            }
        } else if alarmType == .explicit {
            let existingAlarms = alarms.filter{ $0.isExplicit }
            if (!existingAlarms.isEmpty) {
                for alarm in existingAlarms {
                    try await reschedule(now, alarm)
                }
                return
            }
        } else {
            if let alarm = alarms.first(where: { $0.name == alarmName }) {
                try await reschedule(now, alarm)
                return
            }
        }
        Logger.shared.info("initializing \(alarmName)")
        let alarm = AlarmModel(
            name: alarmName,
            alarmType: alarmType,
            hour: 8,
            minute: 0,
            maybeDayToFire: nextDayToFire,
            nextDayToFire: nextDayToFire,
            isEnabled: false
        )
        if alarmType != .yomTov && alarmType != .saturday && alarmType != .specialSaturday {
            alarm.duration = nil
            alarm.repetitions = 0
        }
        //TODO think about groups and different times?
        if alarmName == SaturdayErevPesach {
            alarm.hour = 6
            alarm.minute = 0
        } else if alarmType == .specialSaturday || ["Shmini Atzeret", "Pesach VII", "Pesach VIII", "Shavuot II"].contains(alarm.name) {
            alarm.hour = 7
            alarm.minute = 30
        } else if alarmType == .national || alarm.name == "Simchat Torah" {
            alarm.hour = 7
            alarm.minute = 0
        } else if alarm.name == "Yom Kippur" {
            alarm.hour = 6
            alarm.minute = 45
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
        } else if alarmType == .minor || alarm.name.starts(with: "Rosh Hashana") {
            alarm.hour = 6
            alarm.minute = 0
        }
        if groupLabel.keys.contains(alarmType) && alarmName != Once {
            alarm.isGrouped = alarm.name != SaturdayErevPesach
        }
        modelContext.insert(alarm)
    }
}
