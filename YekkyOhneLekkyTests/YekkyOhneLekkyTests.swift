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
        let alarm = AlarmModel(name: "weekdays", alarmType: AlarmType.weekDay, daysOfWeek: Set(["Monday"]), hour:8, minute:0, maybeDayToFire: now, nextDayToFire: now, duration: nil, repetitions: 0)
        context.insert(alarm)
        try await AlarmLogic.reschedule(now, context, alarm)
        await AlarmLogic.scheduleNext(now, context)
        print(mock.scheduled)
        #expect(mock.scheduled.values.elementsEqual([ISO8601DateFormatter().date(from:"2026-08-03T12:00:00Z")!]))
    }
    
    @Test func save() throws {
        let now = ISO8601DateFormatter().date(from:"2026-07-15T13:00:00Z")!
        let alarm = AlarmModel(name: "weekdays", alarmType: AlarmType.weekDay, daysOfWeek: Set(["Monday"]), hour:8, minute:0, maybeDayToFire: now, nextDayToFire: now, duration: nil, repetitions: 0)
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
        
        let weekdayAlarm = AlarmModel(name: "Wed,Thu", alarmType: AlarmType.weekDay, daysOfWeek: Set(["Wednesday", "Thursday"]), hour:7, minute:30, maybeDayToFire: tuesday, nextDayToFire: tuesday, isOverridden: true, duration: nil, repetitions: 0)
        context.insert(weekdayAlarm) //in real execution initializeAlarms does this
        weekdayAlarm.nextDayToFire = try AlarmLogic.getNextDayToFire(tuesday, weekdayAlarm)
        try await AlarmLogic.saveAlarm(tuesday, context, weekdayAlarm, Set(), nil)
        #expect(mock.scheduled.values.elementsEqual([at(7, 30, on: wednesday)]))
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: AlarmType.roshChodesh, daysOfWeek: Set(), hour:7, minute:15, maybeDayToFire: tuesday, nextDayToFire: tuesday, duration: nil, repetitions: 0)
        context.insert(roshChodeshAlarm) //in real execution initializeAlarms does this
        roshChodeshAlarm.nextDayToFire = try AlarmLogic.getNextDayToFire(tuesday, roshChodeshAlarm)
        try await AlarmLogic.saveAlarm(tuesday, context, roshChodeshAlarm, Set(), nil)
        #expect(mock.scheduled.values.elementsEqual([at(7, 15, on: wednesday)]))
        
        try await AlarmLogic.reschedule(at(8, 0, on: wednesday), context, weekdayAlarm)
        try await AlarmLogic.reschedule(at(8, 0, on: wednesday), context, roshChodeshAlarm)
        await AlarmLogic.scheduleNext(at(8, 0, on: wednesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 30, on: thursday)])) //rosh chodesh waits its turn
        #expect(try roshChodeshAlarm.getAlarmDateAndTime() == at(7, 15, on: nextRoshChodesh))
    }
    
    @Test func rescheduleBeforeTodaysAlarmLeavesItAlone() async throws {
        let tuesday = ISO8601DateFormatter().date(from:"2026-07-14T05:00:00Z")! //in a week in which wednesday is rosh chodesh
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        
        let roshChodeshAlarm = AlarmModel(name: "Rosh Chodesh", alarmType: AlarmType.roshChodesh, daysOfWeek: Set(), hour:7, minute:15, maybeDayToFire: tuesday, nextDayToFire: tuesday, duration: nil, repetitions: 0)
        context.insert(roshChodeshAlarm)
        roshChodeshAlarm.maybeDayToFire = try AlarmLogic.getNextDayToFire(tuesday, roshChodeshAlarm)
        roshChodeshAlarm.nextDayToFire = roshChodeshAlarm.maybeDayToFire
        try await AlarmLogic.saveAlarm(tuesday, context, roshChodeshAlarm, Set(), nil)
        #expect(mock.scheduled.values.elementsEqual([at(7, 15, on: wednesday)]))
        
        //the hourly background refresh runs shortly before the alarm, on its day
        try await AlarmLogic.reschedule(at(6, 30, on: wednesday), context, roshChodeshAlarm)
        await AlarmLogic.scheduleNext(at(6, 30, on: wednesday), context)
        #expect(try roshChodeshAlarm.getAlarmDateAndTime() == at(7, 15, on: wednesday))
        #expect(mock.scheduled.values.elementsEqual([at(7, 15, on: wednesday)]))
    }
    
    @Test func onlyOneAlarmModelScheduledAtATime() async throws {
        let monday = ISO8601DateFormatter().date(from:"2026-08-03T05:00:00Z")!
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        let first = AlarmModel(name: "first", alarmType: .explicit, hour: 7, minute: 0, maybeDayToFire: tuesday, nextDayToFire: tuesday, duration: nil, repetitions: 0)
        let second = AlarmModel(name: "second", alarmType: .explicit, hour: 7, minute: 0, maybeDayToFire: wednesday, nextDayToFire: wednesday, duration: nil, repetitions: 0)
        context.insert(first)
        context.insert(second)
        
        await AlarmLogic.scheduleNext(monday, context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 0, on: tuesday)]))
        
        //the first one's time isn't past yet, so nothing more gets scheduled
        await AlarmLogic.scheduleNext(at(6, 59, on: tuesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 0, on: tuesday)]))
        #expect(second.ids.isEmpty)
        
        //once it's past, the next one is scheduled (the first is left alone in case it's still ringing)
        await AlarmLogic.scheduleNext(at(7, 1, on: tuesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 0, on: tuesday), at(7, 0, on: wednesday)]))
        
        //an earlier alarm added later replaces the one that's waiting
        let earlier = AlarmModel(name: "earlier", alarmType: .explicit, hour: 9, minute: 0, maybeDayToFire: tuesday, nextDayToFire: tuesday, duration: nil, repetitions: 0)
        context.insert(earlier)
        await AlarmLogic.scheduleNext(at(8, 0, on: tuesday), context)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 0, on: tuesday), at(9, 0, on: tuesday)]))
        #expect(second.ids.isEmpty)
    }

    @Test func disablingOverrideRestoresOverriddenAlarm() async throws {
        let sunday = ISO8601DateFormatter().date(from:"2026-08-02T16:00:00Z")! //sunday afternoon, so the day after is already past 9am
        let monday = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        
        let weekdayAlarm = AlarmModel(name: "Monday", alarmType: .weekDay, daysOfWeek: Set(["Monday"]), hour: 9, minute: 0, maybeDayToFire: sunday, nextDayToFire: sunday, duration: nil, repetitions: 0)
        context.insert(weekdayAlarm)
        try await AlarmLogic.saveAlarm(sunday, context, weekdayAlarm, Set(["Monday"]), nil)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(9, 0, on: monday)]))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let override = AlarmModel(name: dateFormatter.string(from: monday), alarmType: .explicit, hour: 10, minute: 0, maybeDayToFire: monday, nextDayToFire: monday, duration: nil, repetitions: 0)
        context.insert(override)
        try await AlarmLogic.saveAlarm(sunday, context, override, Set(), nil)
        #expect(weekdayAlarm.isOverridden)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(10, 0, on: monday)]))
        
        let originalDayToFire = override.nextDayToFire //as EditAlarmView passes it when disabling
        override.isEnabled = false
        try await AlarmLogic.saveAlarm(sunday, context, override, Set(), originalDayToFire)
        #expect(!weekdayAlarm.isOverridden)
        #expect(mock.scheduled.values.sorted().elementsEqual([at(9, 0, on: monday)]))
    }
        
    func at(_ hour: Int, _ minute: Int, on: Date) -> Date {
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: on)!
    }
}
