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
        try await AlarmLogic.reschedule(now, context, alarm)
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
        #expect(mock.scheduled.values.sorted().elementsEqual([at(7, 30, on: thursday), at(7, 15, on: nextRoshChodesh)]))
    }
        
    func at(_ hour: Int, _ minute: Int, on: Date) -> Date {
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: on)!
    }
}
