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
    public static nonisolated let allDaysOfWeek = Calendar.current.standaloneWeekdaySymbols
    public static let groupLabel: [AlarmType: String] = [.yomTov: "yomim tovim", .explicit: "one offs", .national: "nationals", .fast: "fasts", .specialSaturday: "special shabboses"]
    public static var Manager: TestableAlarmManager = AlarmManager.shared
    
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
    
    public class func saveAlarm(_ now: Date, _ modelContext: ModelContext, _ editingAlarm: AlarmModel, _ originalDaysOfWeek: Set<String>, _ originalDayToFire: String?) async throws {
        
        if !editingAlarm.daysOfWeek.isEmpty {
            try await saveWeekDayAlarms(modelContext, editingAlarm, originalDaysOfWeek)
            if originalDayToFire != nil && isHighPriorityWeekday(editingAlarm) {
                try await unoverride(modelContext, nil)
            }
        } else {
            if editingAlarm.name == AlarmLogic.Once && editingAlarm.isEnabled {
                try await saveNewOneOffAlarm(modelContext, editingAlarm)
                if originalDayToFire != nil {
                    try await unoverride(modelContext, originalDayToFire)
                }
            } else {
                try await saveOtherAlarmsInGroup(modelContext, editingAlarm)
                try await saveEditingAlarm(modelContext, editingAlarm)
            }
        }
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
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { $0.alarmTypeRaw == AlarmType.weekDay.rawValue })) {
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
    
    private class func unoverride(_ modelContext: ModelContext, _ day: String?) async throws {
        //an overridden alarm's nextDayToFire was moved past the overridden day, so match on maybeDayToFire, which still has it
        for alarm in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { other in (day == other.maybeDayToFire || day == nil) && other.isOverridden && other.isEnabled && !other.isExtra })) {
            try updateOverrides(modelContext, alarm)
        }
    }
    
    /*
     Currently unsupported: detecting that a weekday alarm in the coming week is overridden by the second day of rosh chodesh, or by the second-and-later days of chol hamoed. Until this is supported, updateOverrides() needs to be called by reschedule() so that we'll get the overrides right by the day before they're needed.
     */
    private class func updateOverrides(_ modelContext: ModelContext, _ alarm: AlarmModel) throws {
        if alarm.isExtra || !alarm.isEnabled {
            return
        }
        
        //Start over from the alarm's first possible day, and advance its date until no other alarm overrides it along the way. If we discover that the other should instead be overridden by this alarm, recurse to handle that.
        alarm.nextDayToFire = alarm.maybeDayToFire
        
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
            for other in try modelContext.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate<AlarmModel> { $0.alarmTypeRaw == AlarmType.weekDay.rawValue })) {
                if !other.isExtra && other.isEnabled && isHighPriorityWeekday(other) {
                    overridingWeekdays.insert(other.daysOfWeek.first!)
                }
            }
        }
        return overridingWeekdays
    }
    
    private class func overrideOneIfConflict(_ modelContext: ModelContext, _ alarm: AlarmModel, _ other: AlarmModel) throws -> AlarmModel? {
        if other.name != alarm.name && other.name != Once && !other.isExtra && other.isEnabled && other.maybeDayToFire == alarm.nextDayToFire {
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
    
    public class func reschedule(_ now: Date, _ modelContext: ModelContext, _ alarm: AlarmModel) async throws {        
        if try alarm.isDue(now) {
            if alarm.alarmType == .explicit {
                alarm.isEnabled = false //to allow e.g. explicit fired at 6am, then at 7am user schedules daily alarm for 8am
                return
            }
            let tomorrow = AlarmModel.addingDays(AlarmModel.day(now), 1)
            alarm.maybeDayToFire = try getNextDayToFire(tomorrow, alarm)
            alarm.nextDayToFire = alarm.maybeDayToFire
            try updateOverrides(modelContext, alarm)
            try modelContext.save()
        } else if try alarm.ids.isEmpty || isFullyScheduled(now, alarm) {
            //not due yet: either waiting its turn (scheduleNext will pick it up), or already handed to AlarmKit intact
            return;
        }
    }
    
    /*
     Hands AlarmKit only a single AlarmModel at a time: the earliest enabled, non-overridden one that hasn't fired yet. While that one's time is still in the future, nothing else is scheduled. Once its time has passed, the next call (from its stopIntent, the background refresh, or opening the app) schedules the one after it.
     */
    public class func scheduleNext(_ now: Date, _ modelContext: ModelContext) async {
        do {
            let next = try getNextAndCancelTheRest(now, modelContext)
            guard let next = next else {
                return
            }
            if !next.ids.isEmpty {
                if try isFullyScheduled(<#Date#>, next) {
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
            
            for _ in 0...next.repetitions {
                try await scheduleOne(date, next, soundConfig)
                if next.duration < AlarmModel.FullDuration {
                    date.addTimeInterval(next.duration)
                    try await scheduleOne(date, next, AlertConfiguration.AlertSound.named("silence.mp3"))
                }
                date.addTimeInterval(next.repetitionDelay)
            }
            try modelContext.save()
        } catch {
            AlarmLogger.shared.error("\(now) Error scheduling next alarm: \(error)")
        }
    }
    
    private class func getNextAndCancelTheRest(_ now: Date, _ modelContext: ModelContext) throws -> AlarmModel? {
        let all = try modelContext.fetch(FetchDescriptor<AlarmModel>())
        
        var upcoming: [(alarm: AlarmModel, date: Date)] = []
        for alarm in all where alarm.isEnabled && !alarm.isOverridden {
            let date = try alarm.getAlarmDateAndTime()
            if date >= now {
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
        try await _ = Manager.schedule(id: uuid, configuration: AlarmManager.AlarmConfiguration<EmptyMetadata>(
            schedule: Alarm.Schedule.fixed(date.advanced(by: -Testable.offset)),
            attributes: attributes,
            stopIntent: ScheduleNextAlarmsIntent(),
            sound: soundConfig
        ))
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
               maybeDayToFire: day(chag), nextDayToFire: day(chag), isEnabled: false, duration: 60, repetitions: 2))
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
        
        if try modelContext.fetchCount(FetchDescriptor(predicate: #Predicate<AlarmModel> { $0.alarmTypeRaw == AlarmType.weekDay.rawValue && $0.name != AlarmModel.Saturday })) == 0 {
            let weekDays = Set(allDaysOfWeek).subtracting([AlarmModel.Saturday])
            let alarm = AlarmModel(name: AlarmModel.nameFromDaysOfWeek(weekDays), alarmType: .weekDay, daysOfWeek: weekDays, hour: 6, minute: 30, maybeDayToFire: today, nextDayToFire: today, isEnabled: false)
            modelContext.insert(alarm)
        }
        
        let saturday = AlarmModel(name: AlarmModel.Saturday, alarmType: .saturday, daysOfWeek: Set([AlarmModel.Saturday]), hour: 8, minute: 0, maybeDayToFire: AlarmModel.never, nextDayToFire: AlarmModel.never, isEnabled: false, duration: 60, repetitions: 2)
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
    func schedule<Metadata>(id: Alarm.ID, configuration: AlarmManager.AlarmConfiguration<Metadata>) async throws -> Alarm where Metadata : AlarmMetadata
}

extension AlarmManager : TestableAlarmManager {}
