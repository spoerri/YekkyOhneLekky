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
    public static nonisolated let SaturdayErevPesach = "Saturday Erev Pesach"
    public static nonisolated let Once = "Just once" //TODO make a separate alarm type from .explicit to avoid forgetting to check?
    public static nonisolated let RoshChodesh = "Rosh Chodesh"
    public static nonisolated let CholHamoed = "Chol Hamoed"
    //Stored day names are always these English ones, Sunday first like Calendar's weekday numbers, so they mean the same whatever the phone's language is or later becomes. Only what's displayed is localized, by index.
    public static nonisolated let allDaysOfWeek = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    public static let groupLabel: [AlarmType: String] = [.yomTov: "yomim tovim", .explicit: "one offs", .national: "nationals", .fast: "fasts", .specialSaturday: "special shabboses"]
    public static var Manager: TestableAlarmManager = AlarmManager.shared
    
    private static let weekDayRaw = AlarmType.weekDay.rawValue
    private static let weekDayPredicate = #Predicate<AlarmModel> { $0.alarmTypeRaw == weekDayRaw }
    
    public class func getEarliest(_ now: Date, _ day: String?) -> Date? {
        //TODO save the location, and keep using the old value if we can't get a new one
        guard let day = day else {
            return nil
        }
        let date = AlarmModel.date(day)
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
    
    private class func getChagim(onOrAfter day: String) -> [HEvent] {
        let htoday = HDate(date: AlarmModel.date(day), calendar: .current)
        
        //TODO allow manually overriding this
        let il = Locale.current.region == Locale.Region.israel
        
        let holidayTypes = HolidayFlags(arrayLiteral: [ .CHAG, .MINOR_FAST, .CHOL_HAMOED, .ROSH_CHODESH, .SPECIAL_SHABBAT ])
            
        let holidayFilter: (HEvent) -> Bool = { ((il && !$0.flags.contains(.CHUL_ONLY)) || (!il && !$0.flags.contains(.IL_ONLY)))
            && (!$0.flags.isDisjoint(with: holidayTypes)
                || $0.desc == "Purim" || $0.desc.contains("Yom Kippur") || $0.desc.contains("Hoshana") || ($0.desc.starts(with:"Chanuka") && !$0.flags.contains(.EREV)))
            }
        
        let thisYears = Hebcal.getAllHolidaysForYear(year: htoday.yy).filter(holidayFilter).filter{ $0.hdate >= htoday }
        //AlarmLogger.shared.info("This year's \(thisYears.map{ $0.hdate.greg() })")
        let thisYearsHolidayNames = thisYears.map({ $0.desc })
        let nextYears = Hebcal.getAllHolidaysForYear(year: htoday.yy+1).filter(holidayFilter).filter{ !thisYearsHolidayNames.contains($0.desc) }
        //AlarmLogger.shared.info("Next year's \(nextYears.map{ $0.hdate.greg() })")
        var all = thisYears + nextYears
        
        all.removeAll(where: {
            $0.flags.contains(.SPECIAL_SHABBAT) && !["Shabbat HaChodesh", "Shabbat Shekalim", "Shabbat HaGadol"].contains($0.desc)
        })
        
        addVayakehlPekudei(&all, htoday.yy, onOrAfter: htoday)
        addVayakehlPekudei(&all, htoday.yy+1, onOrAfter: htoday)
        addForShabbosErevPesach(&all, htoday.yy)
        addForShabbosErevPesach(&all, htoday.yy+1)
        addForShabbosErevSheviiShelPesach(&all, htoday.yy)
        addForShabbosErevSheviiShelPesach(&all, htoday.yy+1)
        addForShabbosChanukah(&all, htoday.yy)
        addForShabbosChanukah(&all, htoday.yy+1)
        
//        let chagimDescription = all.map{$0.desc}; AlarmLogger.shared.info("Chagim \(chagimDescription)")

        return all
    }
    
    private static func addVayakehlPekudei(_ all: inout [HEvent], _ year: Int, onOrAfter htoday: HDate) {
        //only one still to come, like the holidays above; a past one would be found first, so the alarm couldn't move on to the next one, nor lose its day to another alarm
        if let vayakehlPekudei = Sedra(year: year, il: false).find(-21), vayakehlPekudei >= htoday { //dumb api
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
    
    private class func getNextDayOfWeek(onOrAfter day: String, _ daysOfWeek: Set<String>) throws -> String {
        var day = day
        for _ in 0..<allDaysOfWeek.count {
            if daysOfWeek.contains(dayOfWeek(day)) {
                return day
            }
            day = AlarmModel.addingDays(day, 1)
        }
        throw AlarmError.ugh
    }
    
    public static func dayOfWeek(_ day: String) -> String {
        return allDaysOfWeek[Calendar.current.component(.weekday, from: AlarmModel.date(day)) - 1]
    }
        
    //daysOfWeek overrides the alarm's own, e.g. for days picked in EditAlarmView but not saved yet
    public class func getNextDayToFire(_ start: String, _ alarm: AlarmModel, daysOfWeek: Set<String>? = nil) throws -> String {
        let daysOfWeek = daysOfWeek ?? alarm.daysOfWeek
        if alarm.name == Once {
            return start
        }
        if alarm.alarmType == .explicit {
            return alarm.nextDayToFire
        }
        if !daysOfWeek.isEmpty {
            return try getNextDayOfWeek(onOrAfter: start, daysOfWeek)
        }
        if alarm.alarmType == .national {
            return try legalHoliday(onOrAfter: start, alarm.name)
        }
        let chagim = getChagim(onOrAfter: start)
        if let chag = chagim.filter({ $0.desc == alarm.name }).first {
            return day(chag)
        } else if alarm.alarmType == .specialSaturday {
            return AlarmModel.never
        }
        if alarm.alarmType == .cholHamoed {
            if let chag = chagim.filter({ $0.flags.contains(.CHOL_HAMOED) }).first {
                return day(chag)
            }
        }
        if alarm.alarmType == .roshChodesh {
            if let chag = chagim.filter({ $0.flags.contains(.ROSH_CHODESH) }).first {
                return day(chag)
            }
        }
        throw AlarmError.ugh
    }
    
    private static func day(_ chag: HEvent) -> String {
        return AlarmModel.day(chag.hdate.greg())
    }
    
    private class func legalHoliday(onOrAfter day: String, _ name: String) throws -> String {
        guard let legalHoliday = UsHolidays.init(rawValue: name) else {
            throw AlarmError.ugh
        }
        guard let year = Int(day.prefix(4)) else {
            throw AlarmError.ugh
        }
        let thisYears = try legalHoliday.day(in: year)
        if thisYears >= day {
            return thisYears
        } else {
            return try legalHoliday.day(in: year+1)
        }
    }
    
    //originalDayToFire: the day the alarm was going to ring before this edit, if the edit may have freed it for another alarm (see EditAlarmView)
    public class func saveAlarm(_ now: Date, _ modelContext: ModelContext, _ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>, _ originalDayToFire: String? = nil) async throws {
        if !editingAlarm.daysOfWeek.isEmpty {
            try await saveWeekDayAlarms(modelContext, editingAlarm, originalDaysOfWeek)
        } else if editingAlarm.name == AlarmLogic.Once && editingAlarm.isEnabled {
            try await saveNewOneOffAlarm(modelContext, editingAlarm)
        } else {
            try await saveOtherAlarmsInGroup(modelContext, editingAlarm)
            try await saveEditingAlarm(modelContext, editingAlarm)
        }
        try editingAlarm.unschedule()
        try await unoverride(now, modelContext, originalDayToFire)
        await scheduleNext(now, modelContext)
        printScheduledAlarms()
    }
    
    private static func saveOtherAlarmsInGroup( _ modelContext: ModelContext, _ editingAlarm: AlarmModel) async throws {
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
                    try alarm.unschedule()
                    try updateOverrides(modelContext, alarm)
                }
            }
        }
    }
    
    private static func saveEditingAlarm(_ modelContext: ModelContext, _ editingAlarm: AlarmModel) async throws {
        if editingAlarm.name != AlarmLogic.Once && editingAlarm.alarmType == AlarmType.explicit {
            let alarmName = editingAlarm.nextDayToFire
            if alarmName != editingAlarm.name {
                if let sameNamed = try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { $0.name == alarmName})).first {
                    try sameNamed.unschedule()
                    modelContext.delete(sameNamed)
                }
                editingAlarm.name = alarmName
            }
        }
        try updateOverrides(modelContext, editingAlarm)
    }
    
    private static func saveWeekDayAlarms(_ modelContext: ModelContext, _ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>) async throws {
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
                maybeDayToFire: AlarmModel.never,
                nextDayToFire: AlarmModel.never
            )
            newAlarm.maybeDayToFire = try getNextDayToFire(editingAlarm.maybeDayToFire, newAlarm)
            newAlarm.nextDayToFire = newAlarm.maybeDayToFire
            newAlarm.copyConfigFrom(editingAlarm)
            newAlarm.isEnabled = false
            modelContext.insert(newAlarm)
        }
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: weekDayPredicate)) {
            if !editingAlarm.daysOfWeek.isDisjoint(with: alarm.daysOfWeek) && alarm != editingAlarm {
                alarm.daysOfWeek.subtract(editingAlarm.daysOfWeek)
                if alarm.daysOfWeek.isEmpty {
//                    AlarmLogger.shared.info("dayOfWeek alarm left empty, deleting")
                    try alarm.unschedule()
                    modelContext.delete(alarm)
                } else {
                    alarm.name = AlarmModel.nameFromDaysOfWeek(alarm.daysOfWeek)
                }
            }
        }
        editingAlarm.name = AlarmModel.nameFromDaysOfWeek(editingAlarm.daysOfWeek)
        editingAlarm.maybeDayToFire = try getNextDayToFire(editingAlarm.maybeDayToFire, editingAlarm)
        editingAlarm.nextDayToFire = editingAlarm.maybeDayToFire
        try updateOverrides(modelContext, editingAlarm)
    }
    
    private static func saveNewOneOffAlarm(_ modelContext: ModelContext, _ editingAlarm: AlarmModel) async throws {
        let newAlarm = AlarmModel(
            name: editingAlarm.isExtra ? editingAlarm.nextDayToFire + " " + editingAlarm.timeString : editingAlarm.nextDayToFire,
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
        try updateOverrides(modelContext, newAlarm)
    }
    
    private class func unoverride(_ now: Date, _ modelContext: ModelContext, _ originalDayToFire: String?) async throws {
        let today = AlarmModel.day(now)
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in other.maybeDayToFire != other.nextDayToFire && other.isEnabled && !other.isExtra })) where alarm.maybeDayToFire > today || alarm.maybeDayToFire == originalDayToFire {
            try updateOverrides(modelContext, alarm)
        }
    }
    
    /*
     Currently unsupported: detecting that a weekday alarm in the coming week is overridden by the second day of rosh chodesh, or by the second-and-later days of chol hamoed. Until this is supported, updateOverrides() needs to be called by rescheduleDay() so that we'll get the overrides right by the day before they're needed.
     */
    private class func updateOverrides(_ modelContext: ModelContext, _ alarm: AlarmModel) throws {
        if alarm.isExtra || !alarm.isEnabled {
            return
        }
        
        //Start over from the alarm's first possible day, and advance its date until no other alarm overrides it along the way. If we discover that the other should instead be overridden by this alarm, recurse to handle that.
        alarm.nextDayToFire = alarm.maybeDayToFire
        if alarm.nextDayToFire == AlarmModel.never {
            return //no day to lose, e.g. a special shabbos that doesn't come in the years getChagim() looks at; two such mustn't conflict on never
        }
        
        let overridingWeekdays = try getWeekdaysWithAlarmsThatOverride(modelContext, alarm)
        while overridingWeekdays.contains(dayOfWeek(alarm.nextDayToFire)) {
            alarm.nextDayToFire = try getNextDayToFire(AlarmModel.addingDays(alarm.nextDayToFire, 1), alarm)
        }

        for other in try modelContext.fetch(FetchDescriptor<AlarmModel>(sortBy: [SortDescriptor(\.maybeDayToFire)])) {
            if alarm.daysOfWeek.isEmpty && other.maybeDayToFire > alarm.nextDayToFire {
                return
            }
            let overridden = try overrideOneIfConflict(modelContext, alarm, other)
            if alarm == overridden {
                while overridingWeekdays.contains(dayOfWeek(alarm.nextDayToFire)) {
                    alarm.nextDayToFire = try getNextDayToFire(AlarmModel.addingDays(alarm.nextDayToFire, 1), alarm)
                }
            }
        }
    }
    
    //can really only contain saturday or sunday
    private class func getWeekdaysWithAlarmsThatOverride(_ modelContext: ModelContext, _ alarm: AlarmModel) throws -> Set<String> {
        var overridingWeekdays: Set<String> = []
        if alarm.daysOfWeek.isEmpty && alarm.alarmTypeRaw > AlarmType.national.rawValue {
            for other in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: weekDayPredicate)) {
                if !other.isExtra && other.isEnabled && isHighPriorityWeekday(other) {
                    overridingWeekdays.insert(other.daysOfWeek.first!)
                }
            }
        }
        return overridingWeekdays
    }
    
    private class func overrideOneIfConflict(_ modelContext: ModelContext, _ alarm: AlarmModel, _ other: AlarmModel) throws -> AlarmModel? {
        //an overridden other already rings on its nextDayToFire, and scheduleNext() goes by that, so a conflict on either of its days counts
        if other.name != alarm.name && other.name != Once && !other.isExtra && other.isEnabled && (other.maybeDayToFire == alarm.nextDayToFire || other.nextDayToFire == alarm.nextDayToFire) {
            if other.takesPriorityOver(alarm) {
                alarm.nextDayToFire = try getNextDayToFire(AlarmModel.addingDays(alarm.nextDayToFire, 1), alarm)
                return alarm
            } else {
                AlarmLogger.shared.info("\(alarm.name) overriding existing alarm \(other.name) on \(alarm.nextDayToFire)")
                try updateOverrides(modelContext, other)
                return other
            }
        }
        return nil
    }
    
    private class func isHighPriorityWeekday(_ alarm: AlarmModel) -> Bool {
        return alarm.daysOfWeek == Set([AlarmModel.Saturday]) || alarm.daysOfWeek == Set([AlarmModel.Sunday]);
    }
    
    private static let scheduledTimeZoneKey = "scheduledTimeZone"
    
    //AlarmKit's fixed schedules are absolute instants, so after a time zone change (e.g. a flight) they'd ring at the old zone's local time
    //timeZoneID and defaults are for tests
    public class func unscheduleAllIfTimeZoneChanged(_ modelContext: ModelContext, timeZoneID: String? = nil, defaults: UserDefaults = .standard) async throws {
        NSTimeZone.resetSystemTimeZone() //otherwise the zone is cached for as long as the app keeps running
        let current = timeZoneID ?? TimeZone.current.identifier
        if let previous = defaults.string(forKey: scheduledTimeZoneKey), previous != current {
            AlarmLogger.shared.info("time zone changed from \(previous) to \(current)")
            for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>()) where !alarm.ids.isEmpty {
                try alarm.unschedule()
            }
            try modelContext.save()
        }
        defaults.set(current, forKey: scheduledTimeZoneKey) //only once they're out, so a failure tries again next time
    }
    
    public class func rescheduleAll(_ now: Date, _ modelContext: ModelContext) async throws {
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>()) {
            do {
                if try alarm.isDue(now) {
                    try await rescheduleDay(now, modelContext, alarm)
                }
            } catch {
                AlarmLogger.shared.error("Couldn't reschedule \(alarm.name): \(error)")
            }
        }
    }
    
    public class func rescheduleDay(_ now: Date, _ modelContext: ModelContext, _ dueAlarm: AlarmModel) async throws {
        let today = AlarmModel.day(now)
        let dueDay = dueAlarm.maybeDayToFire
        //filtered all at once before rescheduling any of them, since rescheduling one changes which of the others look overridden
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { $0.maybeDayToFire == dueDay })).filter({ $0 === dueAlarm || $0.isOverridden }) {
            try alarm.unschedule()
            if alarm.alarmType == .explicit {
                alarm.isEnabled = false //to allow e.g. explicit fired at 6am, then at 7am user schedules daily alarm for 8am
                continue
            }
            //From the day after its own day rather than after today, so a run after midnight (e.g. a background refresh at 2am) doesn't skip today for an alarm that was done yesterday. But not before today, nor today if its time has already passed. (For an alarm on never, the day after is 10000-01-01, which sorts before any real day.)
            var earliest = try alarm.getAlarmDateAndTime(today) <= now ? AlarmModel.addingDays(today, 1) : today
            earliest = max(earliest, AlarmModel.addingDays(alarm.maybeDayToFire, 1))
            alarm.maybeDayToFire = try getNextDayToFire(earliest, alarm)
            alarm.nextDayToFire = alarm.maybeDayToFire
            try updateOverrides(modelContext, alarm)
        }
        try modelContext.save()
    }
    
    /*
     Hands AlarmKit only a single AlarmModel at a time: the earliest enabled one that hasn't finished ringing. While it still has rings to come, nothing else is scheduled. Once they're past, the next call (from its stopIntent, the background refresh, or opening the app) schedules the one after it.
     */
    public class func scheduleNext(_ now: Date, _ modelContext: ModelContext) async {
        defer { publishUpcoming(now, modelContext) }
        do {
            let next = try getNextAndCancelTheRest(now, modelContext)
            guard let next = next else {
                return
            }
            if !next.ids.isEmpty {
                if try isFullyScheduled(now, next) {
                    return //already scheduled; wait for its time to pass
                }
                AlarmLogger.shared.info("only partially scheduled!")
                try next.unschedule() //AlarmKit lost some of it, so start over
            }
            let soundConfig = getSound(next)
            var date = try next.getAlarmDateAndTime()
            let repetitions = next.repetitions > 0 ? "x"+String(describing:next.repetitions+1) : ""
            let name = next.name.count > 13 ? next.name.prefix(13) + "…" : next.name
            AlarmLogger.shared.info("schedule \(name): \(date.formatted()) \(repetitions)")
            
            //only rings still to come (e.g. in case it was unscheduled between rings)
            for _ in 0...next.repetitions {
                if date > now {
                    try await scheduleOne(date, next, soundConfig)
                }
                if next.duration < AlarmModel.FullDuration {
                    date.addTimeInterval(next.duration)
                    if date > now {
                        try await scheduleOne(date, next, AlertConfiguration.AlertSound.named("silence.mp3"))
                    }
                }
                date.addTimeInterval(next.repetitionDelay)
            }
            try modelContext.save()
        } catch {
            AlarmLogger.shared.error("\(now) Error scheduling next alarm: \(error)")
        }
    }
    
    //For the Next Alarm widget: each enabled alarm's next ring, soonest first
    public class func publishUpcoming(_ now: Date, _ modelContext: ModelContext) {
        do {
            var upcoming: [UpcomingAlarm] = []
            for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>()) where alarm.isEnabled && alarm.nextDayToFire != AlarmModel.never {
                let date = try alarm.getAlarmDateAndTime()
                if date > now {
                    //one offs are named by their day, which the widget shows anyway
                    let name = alarm.alarmType == .explicit ? (alarm.isExtra ? "Extra" : "One off") : alarm.name
                    upcoming.append(UpcomingAlarm(date: date.advanced(by: -Testable.offset), name: name)) //real time, like what AlarmKit is given
                }
            }
            upcoming.sort { $0.date < $1.date }
            NextAlarmStore.save(Array(upcoming.prefix(10)))
        } catch {
            AlarmLogger.shared.error("Couldn't publish upcoming alarms: \(error)")
        }
    }
    
    private class func getNextAndCancelTheRest(_ now: Date, _ modelContext: ModelContext) throws -> AlarmModel? {
        let all = try modelContext.fetch(FetchDescriptor<AlarmModel>())
        
        var upcoming: [(alarm: AlarmModel, date: Date)] = []
        for alarm in all where alarm.isEnabled && alarm.nextDayToFire != AlarmModel.never {
            //it stays next until its last ring is past, so a refresh between its rings doesn't cancel the rest
            if try alarm.getLastRingDateAndTime() >= now {
                let date = try alarm.getAlarmDateAndTime()
                upcoming.append((alarm, date))
            }
        }
        let next = upcoming.min(by: { $0.date < $1.date })?.alarm

        //whatever AlarmKit has that isn't next comes out, whether or not it belongs to some other AlarmModel
        let keep = Set(next?.ids ?? [])
        for alarm in try Manager.alarms where !keep.contains(alarm.id) {
            if case let .fixed(date) = alarm.schedule {
                if alarm.state == .alerting && now.timeIntervalSince(date) < TimeInterval(15*60) {
                    AlarmLogger.shared.info("currently alerting \(date.formatted())")
                    continue
                }
                AlarmLogger.shared.info("surprising unsched \(date.formatted())")
            } else {
                AlarmLogger.shared.info("surprising unsched \(alarm.id)!")
            }
            try Manager.cancel(id: alarm.id)
        }
        //and the other AlarmModels forget the ids that just came out, so they don't look scheduled
        let remaining = Set(try Manager.alarms.map { $0.id })
        for alarm in all where alarm !== next && !alarm.ids.isEmpty {
            alarm.ids.removeAll(where: { !remaining.contains($0) })
        }
        
        return next
    }
    
    private class func getSound(_ alarm: AlarmModel) -> AlertConfiguration.AlertSound {
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
        return soundConfig
    }
    
    private class func scheduleOne(_ date: Date, _ alarm: AlarmModel, _ soundConfig: AlertConfiguration.AlertSound) async throws {
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(
                alert: AlarmPresentation.Alert(
                    title: getSalutation(alarm: alarm),
                )
            ),
            metadata: EmptyMetadata(),
            tintColor: .black
        )
        let uuid = UUID()
        alarm.ids.append(uuid)
        try await Manager.schedule(id: uuid, configuration: AlarmManager.AlarmConfiguration<EmptyMetadata>(
            schedule: Alarm.Schedule.fixed(date.advanced(by: -Testable.offset)),
            attributes: attributes,
            stopIntent: ScheduleNextAlarmsIntent(alarmID: uuid),
            sound: soundConfig
        ))
    }
    
    public class func dismissAlarm(withID id: UUID, _ now: Date, _ modelContext: ModelContext) async throws {
        guard let alarm = try modelContext.fetch(FetchDescriptor<AlarmModel>()).first(where: { $0.ids.contains(id) }) else {
            AlarmLogger.shared.info("no alarm has id \(id)")
            return
        }
        AlarmLogger.shared.info("unscheduling \(alarm.name)")
        try alarm.unschedule()
        try modelContext.save()
        try await AlarmLogic.rescheduleDay(now, modelContext, alarm)
    }
    
    public class func isFullyScheduled(_ now: Date, _ alarm: AlarmModel) throws -> Bool {
        //TODO don't count the ones in the past
        let scheduled = try Manager.alarms.map { $0.id }
        let unscheduled_count = Set(alarm.ids).subtracting(scheduled).count
        if alarm.ids.count > unscheduled_count && unscheduled_count > 0 {
            AlarmLogger.shared.info("partially unscheduled! i.e. \(unscheduled_count)")
        }
        return alarm.ids.count > 0 && unscheduled_count == 0
    }
    
    struct EmptyMetadata : AlarmMetadata {
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
    public static func initializeAlarms(_ today: String, _ modelContext: ModelContext) async throws {
        let chagim = getChagim(onOrAfter: today)
        
        let nextCholHamoed = day(chagim.first{ $0.flags.contains(.CHOL_HAMOED)}!)
        insert(modelContext, AlarmModel(name: CholHamoed, alarmType: .cholHamoed, hour: 6, minute: 30,
            maybeDayToFire: nextCholHamoed, nextDayToFire: nextCholHamoed, isEnabled: false))
        
        let nextRoshChodesh = day(chagim.first{ $0.flags.contains(.ROSH_CHODESH)}!)
        insert(modelContext, AlarmModel(name: RoshChodesh, alarmType: .roshChodesh, hour: 6, minute: 15,
                                        maybeDayToFire: nextRoshChodesh, nextDayToFire: nextRoshChodesh, isEnabled: false))
        
        for chag in chagim.filter({ $0.flags.contains(.SPECIAL_SHABBAT)}) {
            insert(modelContext, AlarmModel( name: chag.desc, alarmType: .specialSaturday, hour: 7, minute: 30,
                                             maybeDayToFire: day(chag), nextDayToFire: day(chag), isEnabled: false, duration: AlarmModel.ChagDefaultDuration, repetitions: 2))
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
            insert(modelContext, AlarmModel(name: chag.desc, alarmType: .yomTov, hour: hour, minute: minute, maybeDayToFire: day(chag), nextDayToFire: day(chag), isEnabled: false))
        }

        for chag in chagim.filter({ $0.flags.isDisjoint(with: [.CHOL_HAMOED, .ROSH_CHODESH, .SPECIAL_SHABBAT, .CHAG]) }) {
            let hour = 6
            var minute = 0
            var alarmType = AlarmType.minor
            if chag.flags.contains(.MINOR_FAST) || chag.desc == "Tish'a B'Av" {
                minute = 15
                alarmType = .fast
            }
            insert(modelContext, AlarmModel(name: chag.desc, alarmType: alarmType, hour: hour, minute: minute, maybeDayToFire: day(chag), nextDayToFire: day(chag), isEnabled: false))
        }
        
        for national in UsHolidays.allCases {
            do {
                let d = try legalHoliday(onOrAfter: AlarmModel.addingDays(today, 1), national.rawValue)
                insert(modelContext, AlarmModel(name: national.rawValue, alarmType: .national, hour: 7, minute: 0,
                    maybeDayToFire: d, nextDayToFire: d, isEnabled: false))
            } catch {
                AlarmLogger.shared.error("Couldn't initialize legal holiday: \(error)")
            }
        }
        
        if try modelContext.fetchCount(FetchDescriptor(predicate: weekDayPredicate)) == 0 {
            let weekDays = Set(allDaysOfWeek).subtracting([AlarmModel.Saturday])
            let alarm = AlarmModel(name: AlarmModel.nameFromDaysOfWeek(weekDays), alarmType: .weekDay, daysOfWeek: weekDays, hour: 6, minute: 30, maybeDayToFire: today, nextDayToFire: today, isEnabled: false)
            modelContext.insert(alarm)
        }
        
        let saturday = AlarmModel(name: AlarmModel.Saturday, alarmType: .saturday, daysOfWeek: Set([AlarmModel.Saturday]), hour: 8, minute: 0, maybeDayToFire: AlarmModel.never, nextDayToFire: AlarmModel.never, isEnabled: false, duration: AlarmModel.ChagDefaultDuration, repetitions: 2)
        saturday.maybeDayToFire = try getNextDayToFire(today, saturday)
        saturday.nextDayToFire = saturday.maybeDayToFire
        insert(modelContext, saturday)

        insert(modelContext, AlarmModel(name: Once, alarmType: .explicit, hour: 8, minute: 0,
            maybeDayToFire: today, nextDayToFire: today, isEnabled: false))
        
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
    @discardableResult func schedule<Metadata>(id: Alarm.ID, configuration: AlarmManager.AlarmConfiguration<Metadata>) async throws -> Alarm where Metadata : AlarmMetadata
}

extension AlarmManager : TestableAlarmManager {}
