import Testing
@testable import YekkyOhneLekky
import Foundation
import SwiftData
import AlarmKit

@MainActor
struct YekkyOhneLekkyTests {
    let container: ModelContainer
    let context: ModelContext
    let mock: MockAlarmManager

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: AlarmModel.self, configurations: config)
        self.context = container.mainContext
        self.mock = MockAlarmManager()
        AlarmLogic.Manager = self.mock
    }
    
    class MockAlarmManager : TestableAlarmManager {
        var alarms: [Alarm] = []
        var scheduled: [Alarm.ID: Date] = [:]
        
        func cancel(id: Alarm.ID) throws {
            alarms.removeAll(where: { $0.id == id })
            scheduled.removeValue(forKey: id)
        }
        
        //TODO what if collision?
        func schedule<Metadata>(id: Alarm.ID, configuration: AlarmManager.AlarmConfiguration<Metadata>) async throws -> Alarm where Metadata : AlarmMetadata {
            
            if let date = Mirror(reflecting: configuration).descendant("schedule", 0, 0) as? Date {
                scheduled[id] = date
            
                if let data = """
    {"id":"\(id)","schedule":{"fixed":{"_0":\(date.timeIntervalSinceReferenceDate)}},"state":{"scheduled":{}}}
    """.data(using: .utf8) {
                    if var alarm = try? JSONDecoder().decode(Alarm.self, from: data) {
                        alarm.id = id
                        alarms.append(alarm)
                        return alarm
                    }
                }
            }
            throw AlarmError.ugh
        }
    }

    @Test func example() async throws {
        let now = ISO8601DateFormatter().date(from:"2026-08-02T13:00:00Z")!
        let alarm = AlarmModel(name: "weekdays", alarmType: AlarmType.weekDay, daysOfWeek: Set(["Monday"]), hour:8, minute:0, maybeDayToFire: AlarmModel.day(now), nextDayToFire: AlarmModel.day(now), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(alarm)
        try await AlarmLogic.rescheduleAll(now, context)
        await AlarmLogic.scheduleNext(now, context)
        print(mock.scheduled)
        #expect(mock.scheduled.values.elementsEqual([ISO8601DateFormatter().date(from:"2026-08-03T12:00:00Z")!]))
    }
    
    @Test func save() throws {
        let now = ISO8601DateFormatter().date(from:"2026-07-15T13:00:00Z")!
        let alarm = AlarmModel(name: "weekdays", alarmType: AlarmType.weekDay, daysOfWeek: Set(["Monday"]), hour:8, minute:0, maybeDayToFire: AlarmModel.day(now), nextDayToFire: AlarmModel.day(now), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(alarm)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<AlarmModel>())
        #expect(fetched.count == 1)
    }

    @Test func afterRoshChodesh() async throws {
        let tuesday = ISO8601DateFormatter().date(from:"2026-07-14T05:00:00Z")! //in a week in which wednesday is rosh chodesh
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        let thursday = Calendar.current.date(byAdding: .day, value: 1, to: wednesday)!
        let nextRoshChodesh = Calendar.current.date(byAdding: .day, value: 30, to: tuesday)!
        
        let weekdayAlarm = AlarmModel(name: "Wed,Thu", alarmType: AlarmType.weekDay, daysOfWeek: Set(["Wednesday", "Thursday"]), hour:7, minute:30, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(weekdayAlarm) //in real execution initializeAlarms does this
        weekdayAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(tuesday), weekdayAlarm)
        weekdayAlarm.nextDayToFire = weekdayAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(tuesday, context, weekdayAlarm, Set())
        #expect(mock.scheduled.values.elementsEqual([at(7, 30, on: wednesday)]))
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: AlarmType.roshChodesh, daysOfWeek: Set(), hour:7, minute:15, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(roshChodeshAlarm) //in real execution initializeAlarms does this
        roshChodeshAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(tuesday), roshChodeshAlarm)
        roshChodeshAlarm.nextDayToFire = roshChodeshAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(tuesday, context, roshChodeshAlarm, Set())
        #expect(mock.scheduled.values.elementsEqual([at(7, 15, on: wednesday)]))
        
        try await AlarmLogic.rescheduleAll(at(8, 0, on: wednesday), context)
        await AlarmLogic.scheduleNext(at(8, 0, on: wednesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 30, on: thursday)])) //rosh chodesh waits its turn
        #expect(try roshChodeshAlarm.getAlarmDateAndTime() == at(7, 15, on: nextRoshChodesh))
    }
    
    @Test func sundayBeatsRoshChodesh() async throws {
        let saturday = ISO8601DateFormatter().date(from:"2026-10-10T13:00:00Z")! //sunday 2026-10-11 is rosh chodesh cheshvan
        let sunday = Calendar.current.date(byAdding: .day, value: 1, to: saturday)!
        
        let sundayAlarm = AlarmModel(name: "Sun", alarmType: AlarmType.weekDay, daysOfWeek: Set(["Sunday"]), hour:8, minute:0, maybeDayToFire: AlarmModel.day(saturday), nextDayToFire: AlarmModel.day(saturday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(sundayAlarm)
        sundayAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(saturday), sundayAlarm)
        sundayAlarm.nextDayToFire = sundayAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(saturday, context, sundayAlarm, Set())
        #expect(mock.scheduled.values.elementsEqual([at(8, 0, on: sunday)]))
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: AlarmType.roshChodesh, daysOfWeek: Set(), hour:6, minute:15, maybeDayToFire: AlarmModel.day(saturday), nextDayToFire: AlarmModel.day(saturday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(roshChodeshAlarm)
        roshChodeshAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(saturday), roshChodeshAlarm)
        roshChodeshAlarm.nextDayToFire = roshChodeshAlarm.maybeDayToFire
        #expect(roshChodeshAlarm.maybeDayToFire == AlarmModel.day(sunday))
        try await AlarmLogic.saveAlarm(saturday, context, roshChodeshAlarm, Set())
        
        //sunday has national holiday precedence, so it beats rosh chodesh, whichever is saved first
        #expect(!sundayAlarm.isOverridden)
        #expect(roshChodeshAlarm.isOverridden)
        #expect(mock.scheduled.values.elementsEqual([at(8, 0, on: sunday)]))
        
        //and saving the sunday alarm again keeps it that way
        try await AlarmLogic.saveAlarm(saturday, context, sundayAlarm, Set(["Sunday"]))
        #expect(!sundayAlarm.isOverridden)
        #expect(roshChodeshAlarm.isOverridden)
        #expect(mock.scheduled.values.elementsEqual([at(8, 0, on: sunday)]))
    }
    
    @Test func sundayBeatsRoshChodeshWeeksAhead() async throws {
        let saturday = ISO8601DateFormatter().date(from:"2026-09-19T13:00:00Z")! //the next rosh chodesh is sunday 2026-10-11, three weeks away
        let sunday = Calendar.current.date(byAdding: .day, value: 1, to: saturday)!
        
        let sundayAlarm = AlarmModel(name: "Sunday", alarmType: AlarmType.weekDay, daysOfWeek: Set(["Sunday"]), hour:8, minute:0, maybeDayToFire: AlarmModel.day(saturday), nextDayToFire: AlarmModel.day(saturday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(sundayAlarm)
        sundayAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(saturday), sundayAlarm)
        sundayAlarm.nextDayToFire = sundayAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(saturday, context, sundayAlarm, Set())
        #expect(sundayAlarm.nextDayToFire == AlarmModel.day(sunday)) //its next occurrence is this week, before rosh chodesh
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: AlarmType.roshChodesh, daysOfWeek: Set(), hour:6, minute:15, maybeDayToFire: AlarmModel.day(saturday), nextDayToFire: AlarmModel.day(saturday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(roshChodeshAlarm)
        roshChodeshAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(saturday), roshChodeshAlarm)
        roshChodeshAlarm.nextDayToFire = roshChodeshAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(saturday, context, roshChodeshAlarm, Set())
        
        #expect(!sundayAlarm.isOverridden)
        #expect(roshChodeshAlarm.isOverridden)
    }
    
    @Test func rescheduleBeforeTodaysAlarmLeavesItAlone() async throws {
        let tuesday = ISO8601DateFormatter().date(from:"2026-07-14T05:00:00Z")! //in a week in which wednesday is rosh chodesh
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: AlarmType.roshChodesh, daysOfWeek: Set(), hour:7, minute:15, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(roshChodeshAlarm)
        roshChodeshAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(tuesday), roshChodeshAlarm)
        roshChodeshAlarm.nextDayToFire = roshChodeshAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(tuesday, context, roshChodeshAlarm, Set())
        #expect(mock.scheduled.values.elementsEqual([at(7, 15, on: wednesday)]))
        
        //the hourly background refresh runs shortly before the alarm, on its day
        try await AlarmLogic.rescheduleAll(at(6, 30, on: wednesday), context)
        await AlarmLogic.scheduleNext(at(6, 30, on: wednesday), context)
        #expect(try roshChodeshAlarm.getAlarmDateAndTime() == at(7, 15, on: wednesday))
        #expect(mock.scheduled.values.elementsEqual([at(7, 15, on: wednesday)]))
    }
    
    @Test func onlyOneAlarmModelScheduledAtATime() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T05:00:00Z")!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        let first = AlarmModel(name: "first", alarmType: .explicit, hour: 7, minute: 0, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: AlarmModel.FullDuration, repetitions: 0)
        let second = AlarmModel(name: "second", alarmType: .explicit, hour: 7, minute: 0, maybeDayToFire: AlarmModel.day(wednesday), nextDayToFire: AlarmModel.day(wednesday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(first)
        context.insert(second)
        
        await AlarmLogic.scheduleNext(monday, context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 0, on: tuesday)]))
        
        //the first one's time isn't past yet, so nothing more gets scheduled
        await AlarmLogic.scheduleNext(at(6, 59, on: tuesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 0, on: tuesday)]))
        #expect(second.ids.isEmpty)
        
        //once it's past, the next one is scheduled and the first comes out (it would be left only if it were ringing)
        await AlarmLogic.scheduleNext(at(7, 1, on: tuesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 0, on: wednesday)]))
        
        //an earlier alarm added later replaces the one that's waiting
        let earlier = AlarmModel(name: "earlier", alarmType: .explicit, hour: 9, minute: 0, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(earlier)
        await AlarmLogic.scheduleNext(at(8, 0, on: tuesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(9, 0, on: tuesday)]))
        #expect(second.ids.isEmpty)
    }

    @Test func disablingOverrideRestoresOverriddenAlarm() async throws {
        let sunday = ISO8601DateFormatter().date(from:"2026-08-02T16:00:00Z")! //sunday afternoon, so the day after is already past 9am
        let monday = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        
        let weekdayAlarm = AlarmModel(name: "Monday", alarmType: .weekDay, daysOfWeek: Set(["Monday"]), hour: 9, minute: 0, maybeDayToFire: AlarmModel.day(sunday), nextDayToFire: AlarmModel.day(sunday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(weekdayAlarm)
        try await AlarmLogic.saveAlarm(sunday, context, weekdayAlarm, Set(["Monday"]))
        #expect(mock.scheduled.values.sorted().elementsEqual([at(9, 0, on: monday)]))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let override = AlarmModel(name: dateFormatter.string(from: monday), alarmType: .explicit, hour: 10, minute: 0, maybeDayToFire: AlarmModel.day(monday), nextDayToFire: AlarmModel.day(monday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(override)
        try await AlarmLogic.saveAlarm(sunday, context, override, Set())
        #expect(weekdayAlarm.isOverridden)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(10, 0, on: monday)]))
        
        let originalDayToFire = override.nextDayToFire //as EditAlarmView passes it when disabling
        override.isEnabled = false
        try await AlarmLogic.saveAlarm(sunday, context, override, Set(), originalDayToFire)
        #expect(!weekdayAlarm.isOverridden)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(9, 0, on: monday)]))
    }

    //bug: changing the time of the alarm that's already handed to AlarmKit left it ringing at the old time
    @Test func editingTheScheduledAlarmsTimeReschedulesIt() async throws {
        let sunday = ISO8601DateFormatter().date(from:"2026-08-02T16:00:00Z")!
        let monday = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        let alarm = AlarmModel(name: "Monday", alarmType: .weekDay, daysOfWeek: Set(["Monday"]), hour: 8, minute: 0, maybeDayToFire: AlarmModel.day(sunday), nextDayToFire: AlarmModel.day(sunday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(alarm)
        try await AlarmLogic.saveAlarm(sunday, context, alarm, Set(["Monday"]))
        #expect(mock.scheduled.values.sorted().elementsEqual([at(8, 0, on: monday)]))
        
        alarm.hour = 9 //as EditAlarmView does
        try await AlarmLogic.saveAlarm(sunday, context, alarm, Set(["Monday"]))
        #expect(mock.scheduled.values.sorted().elementsEqual([at(9, 0, on: monday)]))
        
        alarm.hour = 7
        alarm.duration = 60
        alarm.repetitions = 1
        try await AlarmLogic.saveAlarm(sunday, context, alarm, Set(["Monday"]))
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 0, on: monday), at(7, 1, on: monday), at(7, 5, on: monday), at(7, 6, on: monday)]))
    }
    
    //bug: an overridden alarm wasn't schedulable until its overridden day's time had passed, so stopping an earlier alarm on that day scheduled something far off instead of tomorrow's
    @Test func stoppingRoshChodeshSchedulesTomorrowsWeekdayAlarm() async throws {
        let tuesday = ISO8601DateFormatter().date(from:"2026-07-14T05:00:00Z")! //in a week in which wednesday is rosh chodesh, for one day
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        let thursday = Calendar.current.date(byAdding: .day, value: 1, to: wednesday)!
        
        let weekdayAlarm = AlarmModel(name: "Wed,Thu", alarmType: .weekDay, daysOfWeek: Set(["Wednesday", "Thursday"]), hour: 7, minute: 30, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(weekdayAlarm)
        weekdayAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(tuesday), weekdayAlarm)
        weekdayAlarm.nextDayToFire = weekdayAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(tuesday, context, weekdayAlarm, Set())
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: .roshChodesh, hour: 7, minute: 15, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(roshChodeshAlarm)
        roshChodeshAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(tuesday), roshChodeshAlarm)
        roshChodeshAlarm.nextDayToFire = roshChodeshAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(tuesday, context, roshChodeshAlarm, Set())
        #expect(weekdayAlarm.isOverridden)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 15, on: wednesday)]))
        
        //the person stops the rosh chodesh alarm at 7:16, before the weekday alarm's (overridden) 7:30
        try await AlarmLogic.rescheduleAll(at(7, 16, on: wednesday), context)
        await AlarmLogic.scheduleNext(at(7, 16, on: wednesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 30, on: thursday)]))
    }
    
    //An overridden alarm rings on its nextDayToFire, so losing that day has to count too: e.g. the weekday alarm loses rosh chodesh's first day and moves to its second, where rosh chodesh only arrives once its first day has rung. And it mustn't go back to the first day, where rosh chodesh already rang.
    @Test func twoDayRoshChodeshOverridesBothDays() async throws {
        let saturday = ISO8601DateFormatter().date(from:"2026-10-10T16:00:00Z")! //rosh chodesh cheshvan is sunday 2026-10-11 and monday 2026-10-12
        let sunday = Calendar.current.date(byAdding: .day, value: 1, to: saturday)!
        let monday = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        
        let weekdayAlarm = AlarmModel(name: "Sun,Mon,Tue", alarmType: .weekDay, daysOfWeek: Set(["Sunday", "Monday", "Tuesday"]), hour: 6, minute: 30, maybeDayToFire: AlarmModel.day(saturday), nextDayToFire: AlarmModel.day(saturday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(weekdayAlarm)
        weekdayAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(saturday), weekdayAlarm)
        weekdayAlarm.nextDayToFire = weekdayAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(saturday, context, weekdayAlarm, Set())
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: .roshChodesh, hour: 6, minute: 0, maybeDayToFire: AlarmModel.day(saturday), nextDayToFire: AlarmModel.day(saturday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(roshChodeshAlarm)
        roshChodeshAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(saturday), roshChodeshAlarm)
        roshChodeshAlarm.nextDayToFire = roshChodeshAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(saturday, context, roshChodeshAlarm, Set())
        try #require(roshChodeshAlarm.maybeDayToFire == AlarmModel.day(sunday))
        #expect(weekdayAlarm.nextDayToFire == AlarmModel.day(monday))
        
        //once the first day's ring is over, rosh chodesh moves to its second day, which the weekday alarm then loses too
        try await AlarmLogic.rescheduleAll(at(6, 20, on: sunday), context)
        await AlarmLogic.scheduleNext(at(6, 20, on: sunday), context)
        #expect(roshChodeshAlarm.nextDayToFire == AlarmModel.day(monday))
        #expect(weekdayAlarm.nextDayToFire == AlarmModel.day(tuesday))
        #expect(mock.scheduled.values.sorted().elementsEqual([at(6, 0, on: monday)]))
        
        try await AlarmLogic.rescheduleAll(at(6, 20, on: monday), context)
        await AlarmLogic.scheduleNext(at(6, 20, on: monday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(6, 30, on: tuesday)]))
    }
    
    //bug: an alarm was moved on from the day after the run rather than the day after its own day, so a run after midnight skipped today's alarm
    @Test func runAfterMidnightDoesntSkipToday() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T05:00:00Z")!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let weekdayAlarm = AlarmModel(name: "Mon,Tue", alarmType: .weekDay, daysOfWeek: Set(["Monday", "Tuesday"]), hour: 6, minute: 30, maybeDayToFire: AlarmModel.day(monday), nextDayToFire: AlarmModel.day(monday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(weekdayAlarm)
        
        //monday's ring went unstopped, and the next run is a background refresh at 2am tuesday
        try await AlarmLogic.rescheduleAll(at(2, 0, on: tuesday), context)
        await AlarmLogic.scheduleNext(at(2, 0, on: tuesday), context)
        #expect(weekdayAlarm.maybeDayToFire == AlarmModel.day(tuesday))
        #expect(mock.scheduled.values.sorted().elementsEqual([at(6, 30, on: tuesday)]))
    }
    
    //and when the first run after that is past today's time too, it goes straight on to its next day rather than to today's, which is gone
    @Test func runAfterTodaysTimeGoesOnToTheNextDay() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T05:00:00Z")!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        let weekdayAlarm = AlarmModel(name: "Mon,Tue,Wed", alarmType: .weekDay, daysOfWeek: Set(["Monday", "Tuesday", "Wednesday"]), hour: 6, minute: 30, maybeDayToFire: AlarmModel.day(monday), nextDayToFire: AlarmModel.day(monday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(weekdayAlarm)
        
        //no run between monday's ring and 9am tuesday
        try await AlarmLogic.rescheduleAll(at(9, 0, on: tuesday), context)
        await AlarmLogic.scheduleNext(at(9, 0, on: tuesday), context)
        #expect(weekdayAlarm.maybeDayToFire == AlarmModel.day(wednesday))
        #expect(mock.scheduled.values.sorted().elementsEqual([at(6, 30, on: wednesday)]))
    }
    
    //bug: two alarms of the same priority on one day (e.g. Vayakhel Pekudei on Shabbat HaChodesh) each overrode the other, recursing until the app crashed
    @Test func samePriorityAlarmsOnOneDayHaveAWinner() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T16:00:00Z")!
        let saturday = "2026-08-08"
        //names that aren't real holidays, so whichever loses has no next day: it should wait rather than fail
        let a = AlarmModel(name: "Special A", alarmType: .specialSaturday, hour: 7, minute: 30, maybeDayToFire: saturday, nextDayToFire: saturday, duration: AlarmModel.FullDuration, repetitions: 0)
        let b = AlarmModel(name: "Special B", alarmType: .specialSaturday, hour: 7, minute: 0, maybeDayToFire: saturday, nextDayToFire: saturday, duration: AlarmModel.FullDuration, repetitions: 0)
        #expect(a.takesPriorityOver(b) != b.takesPriorityOver(a))
        context.insert(a)
        context.insert(b)
        try await AlarmLogic.saveAlarm(monday, context, b, Set())
        try await AlarmLogic.saveAlarm(monday, context, a, Set())
        #expect(!a.isOverridden)
        #expect(b.isOverridden)
        #expect(b.nextDayToFire == AlarmModel.never)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 30, on: AlarmModel.date(saturday))]))
    }
    
    //an alarm with no next day yet (e.g. Vayakhel Pekudei in a year it isn't a double parsha) keeps being looked at, and never holds up the rest
    @Test func alarmWaitingForItsNextDayKeepsBeingRescheduled() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T16:00:00Z")!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let waiting = AlarmModel(name: "Not a real shabbos", alarmType: .specialSaturday, hour: 7, minute: 30, maybeDayToFire: "2026-08-01", nextDayToFire: "2026-08-01", duration: AlarmModel.FullDuration, repetitions: 0)
        let weekdayAlarm = AlarmModel(name: "Mon,Tue", alarmType: .weekDay, daysOfWeek: Set(["Monday", "Tuesday"]), hour: 8, minute: 0, maybeDayToFire: AlarmModel.day(monday), nextDayToFire: AlarmModel.day(monday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(waiting)
        context.insert(weekdayAlarm)
        
        try await AlarmLogic.rescheduleAll(monday, context)
        #expect(waiting.maybeDayToFire == AlarmModel.never)
        #expect(try waiting.isDue(monday)) //so the next run looks for its day again
        try await AlarmLogic.rescheduleAll(monday, context)
        #expect(waiting.maybeDayToFire == AlarmModel.never)
        
        await AlarmLogic.scheduleNext(monday, context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(8, 0, on: tuesday)]))
    }
    
    //bug: one alarm that couldn't work out its next day stopped every other alarm from moving on
    @Test func oneAlarmWithNoNextDayDoesntStopTheOthers() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T16:00:00Z")!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let broken = AlarmModel(name: "Not a real shabbos", alarmType: .specialSaturday, hour: 7, minute: 30, maybeDayToFire: "2026-08-01", nextDayToFire: "2026-08-01", duration: AlarmModel.FullDuration, repetitions: 0)
        let weekdayAlarm = AlarmModel(name: "Mon,Tue", alarmType: .weekDay, daysOfWeek: Set(["Monday", "Tuesday"]), hour: 8, minute: 0, maybeDayToFire: AlarmModel.day(monday), nextDayToFire: AlarmModel.day(monday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(broken)
        context.insert(weekdayAlarm)
        try await AlarmLogic.rescheduleAll(monday, context)
        await AlarmLogic.scheduleNext(monday, context)
        #expect(weekdayAlarm.maybeDayToFire == AlarmModel.day(tuesday))
        #expect(mock.scheduled.values.sorted().elementsEqual([at(8, 0, on: tuesday)]))
    }
    
    //bug: disabling the Sunday alarm only restored an alarm it overrode on its own next Sunday, not e.g. rosh chodesh three weeks later
    @Test func disablingSundayAlarmRestoresRoshChodeshWeeksAhead() async throws {
        let saturday = ISO8601DateFormatter().date(from:"2026-09-19T13:00:00Z")! //the next rosh chodesh is sunday 2026-10-11, three weeks away
        let sundayAlarm = AlarmModel(name: "Sunday", alarmType: .weekDay, daysOfWeek: Set(["Sunday"]), hour: 8, minute: 0, maybeDayToFire: AlarmModel.day(saturday), nextDayToFire: AlarmModel.day(saturday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(sundayAlarm)
        sundayAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(saturday), sundayAlarm)
        sundayAlarm.nextDayToFire = sundayAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(saturday, context, sundayAlarm, Set())
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: .roshChodesh, hour: 6, minute: 15, maybeDayToFire: AlarmModel.day(saturday), nextDayToFire: AlarmModel.day(saturday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(roshChodeshAlarm)
        roshChodeshAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(AlarmModel.day(saturday), roshChodeshAlarm)
        roshChodeshAlarm.nextDayToFire = roshChodeshAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(saturday, context, roshChodeshAlarm, Set())
        #expect(roshChodeshAlarm.isOverridden)
        
        sundayAlarm.isEnabled = false
        try await AlarmLogic.saveAlarm(saturday, context, sundayAlarm, Set(["Sunday"]))
        #expect(!roshChodeshAlarm.isOverridden)
    }
    
    //bug: a refresh between an alarm's rings cancelled its remaining repetitions (and the silence cutting the current ring short)
    @Test func refreshBetweenRingsKeepsTheRepetitions() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T05:00:00Z")!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        let first = AlarmModel(name: "first", alarmType: .explicit, hour: 7, minute: 0, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: 60, repetitions: 1, repetitionDelay: 240)
        let second = AlarmModel(name: "second", alarmType: .explicit, hour: 7, minute: 0, maybeDayToFire: AlarmModel.day(wednesday), nextDayToFire: AlarmModel.day(wednesday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(first)
        context.insert(second)
        let rings = [at(7, 0, on: tuesday), at(7, 1, on: tuesday), at(7, 5, on: tuesday), at(7, 6, on: tuesday)]
        
        await AlarmLogic.scheduleNext(monday, context)
        #expect(mock.scheduled.values.sorted().elementsEqual(rings))
        
        //the background refresh at 7:02, after the first ring and its silence
        try await AlarmLogic.rescheduleAll(at(7, 2, on: tuesday), context)
        await AlarmLogic.scheduleNext(at(7, 2, on: tuesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual(rings))
        #expect(first.isEnabled)
    }
    
    @Test func unscheduleAlarmUnschedulesTheWholeAlarmModel() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T05:00:00Z")!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let alarm = AlarmModel(name: "repeating", alarmType: .explicit, hour: 7, minute: 0, maybeDayToFire: AlarmModel.day(tuesday), nextDayToFire: AlarmModel.day(tuesday), duration: 60, repetitions: 1, repetitionDelay: 240)
        context.insert(alarm)
        await AlarmLogic.scheduleNext(monday, context)
        #expect(mock.scheduled.count == 4)
        
        //as the stop intent of its second ring does
        try await AlarmLogic.dismissAlarm(withID: alarm.ids[2], at(7, 5, on: tuesday), context)
        #expect(mock.scheduled.isEmpty)
        #expect(alarm.ids.isEmpty)
        #expect(!alarm.isEnabled) //a one-off is done once it's stopped, so scheduleNext won't put its remaining rings back
        await AlarmLogic.scheduleNext(at(7, 5, on: tuesday), context)
        #expect(mock.scheduled.isEmpty)
        
        //an id that isn't any alarm's is ignored
        try await AlarmLogic.dismissAlarm(withID: UUID(), at(7, 5, on: tuesday), context)
    }
        
    //bug: after a time zone change, the scheduled alarm rang at the old zone's local time
    @Test func timeZoneChangeUnschedulesEverything() async throws {
        let defaults = UserDefaults(suiteName: "timeZoneChangeUnschedulesEverything")!
        defaults.removePersistentDomain(forName: "timeZoneChangeUnschedulesEverything")
        let sunday = ISO8601DateFormatter().date(from:"2026-08-02T16:00:00Z")!
        let monday = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        let alarm = AlarmModel(name: "Monday", alarmType: .weekDay, daysOfWeek: Set(["Monday"]), hour: 8, minute: 0, maybeDayToFire: AlarmModel.day(monday), nextDayToFire: AlarmModel.day(monday), duration: AlarmModel.FullDuration, repetitions: 0)
        context.insert(alarm)
        
        try await AlarmLogic.unscheduleAllIfTimeZoneChanged(context, timeZoneID: "America/New_York", defaults: defaults) //the first run only remembers the zone
        await AlarmLogic.scheduleNext(sunday, context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(8, 0, on: monday)]))
        
        try await AlarmLogic.unscheduleAllIfTimeZoneChanged(context, timeZoneID: "America/New_York", defaults: defaults)
        #expect(mock.scheduled.count == 1) //same zone: left alone
        
        try await AlarmLogic.unscheduleAllIfTimeZoneChanged(context, timeZoneID: "America/Los_Angeles", defaults: defaults)
        #expect(mock.scheduled.isEmpty)
        #expect(alarm.ids.isEmpty)
        await AlarmLogic.scheduleNext(sunday, context)
        #expect(mock.scheduled.count == 1) //scheduled again, at its local time in whatever zone the phone is now in
    }
    
    func at(_ hour: Int, _ minute: Int, on: Date) -> Date {
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: on)!
    }
}
