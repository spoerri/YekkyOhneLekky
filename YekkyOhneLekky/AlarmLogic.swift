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
    public static var Manager: TestableAlarmManager = AlarmManager.shared
    
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
            AlarmLogger.shared.info("Couldn't get current location")
            return nil
        }
        
        //AlarmLogger.shared.info("latitude",currentLocation.coordinate.latitude,"longitude",currentLocation.coordinate.longitude)

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
        //AlarmLogger.shared.info("This year's \(thisYears.map{ $0.hdate.greg() })")
        let thisYearsHolidayNames = thisYears.map({ $0.desc })
        let nextYears = Hebcal.getAllHolidaysForYear(year: htoday.yy+1).filter(holidayFilter).filter{ !thisYearsHolidayNames.contains($0.desc) }
        //AlarmLogger.shared.info("Next year's \(nextYears.map{ $0.hdate.greg() })")
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
        
//        let chagimDescription = all.map{$0.desc}; AlarmLogger.shared.info("Chagim \(chagimDescription)")

        return all
    }
    
    private static func addVayakehlPekudei(_ all: inout [HEvent], _ year: Int) {
        if let vayakehlPekudei = Sedra(year: year, il: false).find(-21) { //dumb api
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
        let year = Calendar.current.component(.year, from: nextDay(now))
        let thisYears = try legalHoliday.date(in: year)
        if thisYears > now {
            return thisYears
        } else {
            return try legalHoliday.date(in: year+1)
        }
    }
    
    public class func saveAlarm(_ now: Date, _ modelContext: ModelContext, _ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>, _ originalDayToFire: Date?) async throws {
        
        if editingAlarm.alarmType == .weekDay {
            try await saveWeekDayAlarms(now, modelContext, editingAlarm, originalDaysOfWeek)
        } else if editingAlarm.name == AlarmLogic.Once && editingAlarm.isEnabled {
            await saveNewOneOffAlarm(now, modelContext, editingAlarm)
        } else {
            try await saveOtherAlarmsInGroup(now, modelContext, editingAlarm)
            try await saveEditingAlarm(now, modelContext, editingAlarm)
        }
        
        if let originalDayToFire = originalDayToFire {
            try await unoverride(now, modelContext, originalDayToFire)
        }
        
        await scheduleNext(now, modelContext)
        try modelContext.save()
        printScheduledAlarms()
    }
    
    private static func saveOtherAlarmsInGroup(_ now: Date, _ modelContext: ModelContext, _ editingAlarm: AlarmModel) async throws {
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
                    await schedule(now, modelContext, alarm)
                }
            }
        }
    }
    
    private static func saveEditingAlarm(_ now: Date, _ modelContext: ModelContext, _ editingAlarm: AlarmModel) async throws {
        if editingAlarm.name != AlarmLogic.Once && editingAlarm.alarmType == AlarmType.explicit {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let alarmName = dateFormatter.string(from: editingAlarm.nextDayToFire)
            if alarmName != editingAlarm.name {
                if let sameNamed = try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { $0.name == alarmName})).first {
                    try sameNamed.unschedule()
                    modelContext.delete(sameNamed)
                }
                editingAlarm.name = alarmName
            }
        }
        await schedule(now, modelContext, editingAlarm)
    }
    
    public class func disablePastOneOffs(_ now: Date, _ modelContext: ModelContext?) throws {
        let endOfToday = Calendar.current.startOfDay(for: now) + TimeInterval(60*60*24)
        if let todays = try modelContext?.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in other.isEnabled && other.nextDayToFire <= endOfToday})) {
            for alarm in todays {
                if alarm.nextDayToFire < now && alarm.alarmType == .explicit && alarm.name != AlarmLogic.Once {
                    alarm.isEnabled = false
                }
            }
        }
    }
    
    private static func saveWeekDayAlarms(_ now:Date, _ modelContext: ModelContext, _ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>) async throws {
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
//                    AlarmLogger.shared.info("dayOfWeek alarm left empty, deleting")
                    try alarm.unschedule()
                    modelContext.delete(alarm)
                } else {
                    alarm.name = AlarmModel.nameFromDaysOfWeek(alarm.daysOfWeek)
                    await schedule(now, modelContext, alarm)
                }
            }
        }
        editingAlarm.name = AlarmModel.nameFromDaysOfWeek(editingAlarm.daysOfWeek)
        editingAlarm.maybeDayToFire = try getNextDayToFire(now, editingAlarm)
        editingAlarm.nextDayToFire = editingAlarm.maybeDayToFire
        await schedule(now, modelContext, editingAlarm)
    }
    
    private static func saveNewOneOffAlarm(_ now: Date, _ modelContext: ModelContext, _ editingAlarm: AlarmModel) async {
        let dateFormatter = DateFormatter()
        if (editingAlarm.isExtra) {
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        } else {
            dateFormatter.dateFormat = "yyyy-MM-dd"
        }
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
        await schedule(now, modelContext, newAlarm)
    }
    
    private class func unoverride(_ now: Date, _ modelContext: ModelContext, _ date: Date) async throws {
        let start = Calendar.current.startOfDay(for: date)
        let stop = start + TimeInterval(60*60*24)
        //an overridden alarm's nextDayToFire was moved past the overridden day, so match on maybeDayToFire, which still has it
        if let overriddenAlarm = try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in start <= other.maybeDayToFire && other.maybeDayToFire < stop && other.isOverridden })).sorted(using: SortDescriptor(\.alarmTypeRaw)).first {
            overriddenAlarm.isOverridden = false
            overriddenAlarm.nextDayToFire = overriddenAlarm.maybeDayToFire 
            await schedule(now, modelContext, overriddenAlarm)
        }
    }
    
    private class func overrideAsAppropriate(_ now: Date, _ modelContext: ModelContext, _ alarm: AlarmModel) throws {
        if alarm.isExtra {
            return
        }
        
        if alarm.isOverridden && Calendar.current.startOfDay(for: alarm.nextDayToFire) == Calendar.current.startOfDay(for: now) {
            return
        }
        
        alarm.isOverridden = false
        
        let alarmName = alarm.name
        let start = Calendar.current.startOfDay(for: alarm.nextDayToFire)
        let stop = start+TimeInterval(60*60*24)
        
//        let sameDayAlarms = try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in
//            start <= other.nextDayToFire && other.nextDayToFire < stop &&
//            other.name != alarmName && !other.isOverridden && other.name != Once}))
        for other in try modelContext.fetch(FetchDescriptor<AlarmModel>()) {
            if !(start <= other.nextDayToFire && other.nextDayToFire < stop &&
                 other.name != alarmName && !other.isOverridden && other.name != Once) {
                continue
            }
            if other.isExtra {
                //extra alarms neither override nor are overridden
            } else if other.alarmType > alarm.alarmType {
                try other.unschedule()
                other.isOverridden = true
                other.nextDayToFire = try getNextDayToFire(nextDay(now), other)
            } else if other.isEnabled {
                alarm.isOverridden = true
                alarm.nextDayToFire = try getNextDayToFire(nextDay(now), alarm)
            }
        }
        
        //if this alarm falls on a saturday or sunday which hasn't been scheduled yet, and is lower priority, and if the saturday/sunday alarm is enabled then override this alarm
        let dayOfWeek = allDaysOfWeek[Calendar.current.component(.weekday, from: alarm.nextDayToFire) - 1]
        if dayOfWeek == Saturday && alarm.alarmType > .saturday {
            try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { other in
                other.isEnabled && other.isShabbos && !other.isExtra })).forEach { _ in
                alarm.isOverridden = true
                alarm.nextDayToFire = try getNextDayToFire(nextDay(now), alarm)
            }
        } else if dayOfWeek == Sunday && alarm.alarmType > .national && alarm.alarmType != .weekDay {
            try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { other in
                other.isEnabled && other.isWeekDay && !other.isExtra })).forEach { other in
                    if other.daysOfWeek.contains(dayOfWeek) {
                        alarm.isOverridden = true
                        alarm.nextDayToFire = try getNextDayToFire(nextDay(now), alarm)
                    }
                }
        }
        
        //TODO what about the converse? enabling/disabling a weekday alarm, override/unoverride any existing same day alarms for those days?
    }
    
    public class func reschedule(_ now: Date, _ modelContext: ModelContext, _ alarm: AlarmModel) async throws {        
        if (alarm.isOnOrBefore(now)) {
            alarm.maybeDayToFire = try getNextDayToFire(now, alarm)
            alarm.nextDayToFire = alarm.maybeDayToFire
            try modelContext.save()
        } else if try alarm.ids.isEmpty || isFullyScheduled(alarm) {
            //not due yet: either waiting its turn (scheduleNext will pick it up), or already handed to AlarmKit intact
            return;
        }
        
        await schedule(now, modelContext, alarm)
    }
    
    //Prepares the alarm (unschedules it, works out overrides) but doesn't hand it to AlarmKit.
    //That happens only in scheduleNext, which schedules a single AlarmModel at a time.
    private class func schedule(_ now: Date, _ modelContext: ModelContext, _ alarm: AlarmModel) async {
        //AlarmLogger.shared.notice("Perhaps scheduling \(alarm.name): \(alarm.nextDayToFire)")
        do {
            try alarm.unschedule()
            
            //TODO disabling from save should check the overrides
            if !alarm.isEnabled {
                return;
            }
            
            try overrideAsAppropriate(now, modelContext, alarm)
        } catch {
            AlarmLogger.shared.error("\(now) Error scheduling alarm: \(error)")
        }
    }
    
    //Hands AlarmKit only a single AlarmModel at a time: the earliest enabled, non-overridden one that hasn't fired yet.
    //While that one's time is still in the future, nothing else is scheduled. Once its time has passed, the next call
    //(from its stopIntent, the background refresh, or opening the app) schedules the one after it.
    public class func scheduleNext(_ now: Date, _ modelContext: ModelContext) async {
        do {
            let all = try modelContext.fetch(FetchDescriptor<AlarmModel>())
            
            var upcoming: [(alarm: AlarmModel, date: Date)] = []
            for alarm in all where alarm.isEnabled && !alarm.isOverridden {
                let date = try alarm.getAlarmDateAndTime()
                if date >= now {
                    upcoming.append((alarm, date))
                }
            }
            let next = upcoming.min(by: { $0.date < $1.date })?.alarm
            
            //anything else that's scheduled and hasn't fired yet comes out, e.g. when an earlier alarm was just saved,
            //or left over from when every alarm was scheduled at once.
            //alarms whose time already passed are left alone, so their repetitions still ring.
            for alarm in all where !alarm.ids.isEmpty && alarm != next {
                if try alarm.getAlarmDateAndTime() >= now {
                    try alarm.unschedule()
                }
            }
            
            guard let next = next else {
                return
            }
            if !next.ids.isEmpty {
                if try isFullyScheduled(next) {
                    return //already scheduled; wait for its time to pass
                }
                try next.unschedule() //AlarmKit lost some of it, so start over
            }
            try await arm(now, next)
            try modelContext.save()
        } catch {
            AlarmLogger.shared.error("\(now) Error scheduling next alarm: \(error)")
        }
    }
    
    private class func arm(_ now: Date, _ alarm: AlarmModel) async throws {
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
                AlarmLogger.shared.info("Custom sound \(selectedSoundName).mp3 not found in bundle, using default")
            }
        } else {
            soundConfig = .default
        }
        //AlarmLogger.shared.info("Using sound: \(soundConfig)")
        
        var date = try alarm.getAlarmDateAndTime()
        let repetitions = alarm.repetitions > 0 ? "x"+String(describing:alarm.repetitions+1) : ""
        let name = alarm.name.count > 13 ? alarm.name.prefix(13) + "…" : alarm.name
        AlarmLogger.shared.info("sched \(name): \(date.formatted()) \(repetitions)")
        
        for _ in 0...alarm.repetitions {
            let uuid = UUID()
            alarm.ids.append(uuid)
            try await scheduleAlarm(now, id: uuid, date: date, soundConfig: soundConfig, attributes: attributes)
            if let duration = alarm.duration {
                date.addTimeInterval(duration)
                let uuid = UUID()
                alarm.ids.append(uuid)
                try await scheduleAlarm(now, id: uuid, date: date, soundConfig: AlertConfiguration.AlertSound.named("silence.mp3"), attributes: attributes)
                date.addTimeInterval(alarm.repetitionDelay)
            }
        }
    }
    
    public class func isFullyScheduled(_ alarm: AlarmModel) throws -> Bool {
        let scheduled = try Manager.alarms.map { $0.id }
        let unscheduled_count = Set(alarm.ids).subtracting(scheduled).count
        if alarm.ids.count > unscheduled_count && unscheduled_count > 0 {
            AlarmLogger.shared.info("partially unscheduled! i.e. \(unscheduled_count)")
        }
        return alarm.ids.count > 0 && unscheduled_count == 0
    }
    
    struct EmptyMetadata : AlarmMetadata {
    }
    
    private class func scheduleAlarm(_ now: Date, id: UUID, date: Date, soundConfig: AlertConfiguration.AlertSound, attributes: AlarmAttributes<EmptyMetadata>) async throws {
        if try Manager.alarms.contains(where: { $0.id == id }) {
            return
        }
        let alarmConfiguration = AlarmManager.AlarmConfiguration<EmptyMetadata>(
            schedule: Alarm.Schedule.fixed(date),
            attributes: attributes,
            stopIntent: ScheduleNextAlarmsIntent(),
            sound: soundConfig
        )
        //AlarmLogger.shared.notice("Scheduling \(id) for \(date)")
        _ = try await Manager.schedule(id: id, configuration: alarmConfiguration)
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
    
    //TODO share more with getNextDayToFire?
    public static func initializeAlarms(_ now: Date, _ modelContext: ModelContext) async throws {
        let chagim = getChagim(now)
        
        let nextCholHamoed = chagim.first{ $0.flags.contains(.CHOL_HAMOED)}!.hdate.greg()
        insert(modelContext, AlarmModel(name: CholHamoed, alarmType: .cholHamoed, hour: 6, minute: 30,
            maybeDayToFire: nextCholHamoed, nextDayToFire: nextCholHamoed, isEnabled: false, repetitions: 0))
        
        let nextRoshChodesh = chagim.first{ $0.flags.contains(.ROSH_CHODESH)}!.hdate.greg()
        insert(modelContext, AlarmModel(name: RoshChodesh, alarmType: .roshChodesh, hour: 6, minute: 15,
           maybeDayToFire: nextRoshChodesh, nextDayToFire: nextRoshChodesh, isEnabled: false, repetitions: 0))
        
        for chag in chagim.filter({ $0.flags.contains(.SPECIAL_SHABBAT)}) {
            insert(modelContext, AlarmModel( name: chag.desc, alarmType: .specialSaturday, hour: 7, minute: 30,
               maybeDayToFire: chag.hdate.greg(), nextDayToFire: chag.hdate.greg(), isEnabled: false))
        }
        
        for chag in chagim.filter({ $0.flags.contains(.CHAG)}) {
            var hour: Int = 8
            var minute: Int = 0
            if ["Shmini Atzeret", "Pesach VIII", "Shavuot II"].contains(chag.desc) {
                hour = 7
                minute = 30
            } else if chag.desc == "Simchat Torah" {
                hour = 7
            } else if chag.desc == "Yom Kippur" {
                hour = 6
                minute = 45
            } else if chag.desc.starts(with: "Rosh Hashana") {
                hour = 6
            }
            insert(modelContext, AlarmModel(name: chag.desc, alarmType: .yomTov, hour: hour, minute: minute, maybeDayToFire: chag.hdate.greg(), nextDayToFire: chag.hdate.greg(), isEnabled: false))
        }

        for chag in chagim.filter({ $0.flags.isDisjoint(with: [.CHOL_HAMOED, .ROSH_CHODESH, .SPECIAL_SHABBAT, .CHAG]) }) {
            let hour = 6
            var minute = 0
            var alarmType = AlarmType.minor
            if chag.flags.contains(.MINOR_FAST) || chag.desc == "Tish'a B'Av" {
                minute = 15
                alarmType = .fast
            }
            insert(modelContext, AlarmModel(name: chag.desc, alarmType: alarmType, hour: hour, minute: minute, maybeDayToFire: chag.hdate.greg(), nextDayToFire: chag.hdate.greg(), isEnabled: false, repetitions: 0))
        }
        
        for national in UsHolidays.allCases {
            do {
                let d = try legalHoliday(now, national.rawValue)
                insert(modelContext, AlarmModel(name: national.rawValue, alarmType: .national, hour: 7, minute: 0,
                    maybeDayToFire: d, nextDayToFire: d, isEnabled: false, repetitions: 0))
            } catch {
                AlarmLogger.shared.error("Couldn't initialize legal holiday: \(error)")
            }
        }
        
        let weekDays = Set(allDaysOfWeek).subtracting([Saturday])
        let alarm = AlarmModel(name: AlarmModel.nameFromDaysOfWeek(weekDays), alarmType: .weekDay, daysOfWeek: weekDays, hour: 6, minute: 30, maybeDayToFire: now, nextDayToFire: now, isEnabled: false, repetitions: 0)
        modelContext.insert(alarm)
        
        let nextSaturday = try getNextDayOfWeek(now, Set([Saturday]), 8, 0)
        insert(modelContext, AlarmModel(name: Saturday, alarmType: .saturday, daysOfWeek: Set([Saturday]), hour: 8, minute: 0, maybeDayToFire: nextSaturday, nextDayToFire: nextSaturday, isEnabled: false))

        insert(modelContext, AlarmModel(name: Once, alarmType: .explicit, hour: 8, minute: 0,
            maybeDayToFire: now, nextDayToFire: now, isEnabled: false))
        
        printScheduledAlarms()
    }
    
    private static func insert(_ modelContext: ModelContext, _ alarm: AlarmModel) {
        do {
            let alarmName = alarm.name
            if try modelContext.fetchCount(FetchDescriptor(predicate: #Predicate<AlarmModel> { $0.name == alarmName})) > 0 {
                return
            }
        } catch {
            AlarmLogger.shared.error("Could not check for already initialized alarm: \(error)")
        }
        if groupLabel.keys.contains(alarm.alarmType) && alarm.name != Once && alarm.name != SaturdayErevPesach {
            alarm.isGrouped = true
        }
        if alarm.name == SaturdayErevPesach { //handled here to not care whether hebcal considers it a special shabbos
            alarm.hour = 6
        }
        AlarmLogger.shared.info("initializeAlarm: \(alarm.name)")
        modelContext.insert(alarm)
    }
    
    public static func printScheduledAlarms() {
        do {
            var timesForDate = [String: [String]]()
            for alarm in try Manager.alarms {
                if case let .fixed(date) = alarm.schedule {
                    let dateKey = date.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits))
                    timesForDate[dateKey, default: []].append(date.formatted(date: .omitted, time: .shortened))
                }
            }
            var timesForDateAbbrev = [String: [String]]()
            for date in timesForDate.keys {
                for time in timesForDate[date]!.sorted() {
                    if timesForDateAbbrev[date] != nil, let colon = time.firstIndex(of: ":") {
                        let hour = time.distance(from: time.startIndex, to: colon)
                        var fullTime = timesForDateAbbrev[date]!.popLast()!
                        if fullTime.prefix(hour) == time.prefix(hour) {
                            fullTime.append(",\(time.dropFirst(hour+1).prefix(2))")
                            timesForDateAbbrev[date]?.append(fullTime)
                            continue
                        }
                    }
                    timesForDateAbbrev[date, default: []].append(time)
                }
            }
            var snapshot = ""
            for date in timesForDate.keys.sorted() {
                snapshot += "* \(date): \(timesForDateAbbrev[date]?.joined(separator: " ") ?? "?")\n"
            }
            AlarmLogger.shared.info("Snapshot:\n\(snapshot)")
            //TODO print configured alarms
        } catch {
            AlarmLogger.shared.error("Couldn't print scheduled alarms: \(error)")
        }
    }
}

protocol TestableAlarmManager {
    nonisolated var alarms: [Alarm] { get throws }
    func cancel(id: Alarm.ID) throws
    func schedule<Metadata>(id: Alarm.ID, configuration: AlarmManager.AlarmConfiguration<Metadata>) async throws -> Alarm where Metadata : AlarmMetadata
}

extension AlarmManager : TestableAlarmManager {}
