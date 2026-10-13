import Foundation
import SwiftData
import Testing
@testable import ParkSignal_AI

@MainActor
final class FakeReminderBackend: ReminderBackend {
    var pending: Set<String> = []
    var scheduled: [PlannedReminder] = []
    var cancelled: [ReminderHandle] = []
    var deny = false
    func pendingKeys() async -> Set<String> { pending }
    func schedule(_ plan: PlannedReminder) async throws -> ReminderHandle {
        if deny { throw AlarmService.AlarmError.notAuthorized }
        scheduled.append(plan)
        let handle = ReminderHandle(notificationID: plan.id)
        pending.insert(handle.key)
        return handle
    }
    func cancel(_ handle: ReminderHandle) async {
        cancelled.append(handle)
        pending.remove(handle.key)
    }
}

@MainActor
@Suite("Device-local reminder lifecycle")
struct ReminderCoordinatorTests {
    private func plan(id: String = "A", offset: Double = 3600) -> PlannedReminder {
        PlannedReminder(id: id, carID: UUID(), spotID: UUID(), fireDate: Date(timeIntervalSince1970: 2_000_000_000 + offset),
                        deadline: Date(timeIntervalSince1970: 2_000_001_000 + offset), title: "Check parking", body: "Rule")
    }
    @Test func reconcileAndRelaunchAreIdempotent() async throws {
        let name = "ReminderTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeReminderBackend(), a = plan()
        let first = ReminderCoordinator(defaults: defaults, backend: backend)
        try await first.apply([a]); try await first.apply([a])
        let relaunched = ReminderCoordinator(defaults: defaults, backend: backend)
        try await relaunched.apply([a])
        #expect(backend.scheduled.count == 1)
        try await relaunched.apply([])
        #expect(backend.cancelled.count == 1)
    }
    @Test func editReplacesAndOtherCarIsUnchanged() async throws {
        let name = "ReminderTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeReminderBackend(), coordinator = ReminderCoordinator(defaults: defaults, backend: backend)
        let a = plan(), b = plan(id: "B")
        try await coordinator.apply([a,b])
        let changed = PlannedReminder(id: a.id, carID: a.carID, spotID: a.spotID, fireDate: a.fireDate.addingTimeInterval(-300), deadline: a.deadline, title: a.title, body: a.body)
        try await coordinator.apply([changed,b])
        #expect(backend.scheduled.count == 3)
        #expect(backend.cancelled.map(\.notificationID) == [a.id])
    }
    @Test func cancelledReminderStaysCancelledAfterRelaunch() async throws {
        let name = "ReminderTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeReminderBackend(), coordinator = ReminderCoordinator(defaults: defaults, backend: backend)
        let a = plan()
        try await coordinator.apply([a])
        coordinator.suppressAll()
        backend.pending = []
        try await ReminderCoordinator(defaults: defaults, backend: backend).apply([a])
        #expect(backend.scheduled.count == 1)
    }
    @Test func permissionDenialIsNotRecordedAsSuccess() async throws {
        let name = "ReminderTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeReminderBackend(), coordinator = ReminderCoordinator(defaults: defaults, backend: backend)
        let a = plan()
        backend.deny = true
        do { try await coordinator.apply([a]); Issue.record("Expected denial") } catch {}
        #expect(backend.scheduled.isEmpty)
        backend.deny = false
        try await coordinator.apply([a])
        #expect(backend.scheduled.count == 1)
    }
    @Test func deliveredOccurrenceIsNotReplayed() async throws {
        let name = "ReminderTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = FakeReminderBackend(), a = plan()
        let coordinator = ReminderCoordinator(defaults: defaults, backend: backend)
        // First enable inside the lead window still schedules promptly.
        let late = a.fireDate.addingTimeInterval(30)
        try await coordinator.apply([a], now: late)
        #expect(backend.scheduled.count == 1)
        backend.pending = [] // Delivered or dismissed by the OS.
        try await coordinator.apply([a], now: late.addingTimeInterval(1))
        #expect(backend.scheduled.count == 1)
    }
    @Test(arguments: ["America/Los_Angeles", "America/New_York", "Europe/London"])
    func windowAndDurationUseSpotTimezone(_ zone: String) throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = try #require(TimeZone(identifier: zone))
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 9)))
        let spot = ParkingSpot(location: "Test", latitude: 1, longitude: 2, streetSide: "right")
        spot.timeZoneIdentifier = zone
        let rule = Restriction(type: .timeLimited,
            startTime: DateTimeUtils.todayAt(hour: 9, minute: 0, ref: now, calendar: cal),
            endTime: DateTimeUtils.todayAt(hour: 18, minute: 0, ref: now, calendar: cal),
            daysOfWeek: [1,2,3,4,5], sourceUser: UUID(), durationMinutes: 120)
        spot.restrictionsList = [rule]
        let session = ParkSession(spot: spot, startedAt: now)
        let planned = ReminderPlanner.plan(sessions: [session], leadMinutes: 15, now: now, calendar: cal)
        #expect(planned.count == 10) // Two work weeks survive without relaunch.
        #expect(planned.first?.deadline == now.addingTimeInterval(7200))
        #expect(planned.first?.fireDate == now.addingTimeInterval(6300))
        #expect(ReminderPlanner.plan(sessions: [session], leadMinutes: 0, now: now, calendar: cal).first?.fireDate == now.addingTimeInterval(7200))
        rule.needsReview = true
        #expect(ReminderPlanner.plan(sessions: [session], leadMinutes: 15, now: now, calendar: cal).isEmpty)
    }
    @Test func overnightAcrossDSTUsesCalendarDays() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let spring = try #require(ISO8601DateFormatter().date(from: "2026-03-08T10:30:00Z")) // Sunday 03:30 after jump
        #expect(DateTimeUtils.isWindowActive(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0, days: [6], now: spring, calendar: cal))
        for time in ["2026-11-01T08:30:00Z", "2026-11-01T09:30:00Z"] { // both 01:30 occurrences
            let fall = try #require(ISO8601DateFormatter().date(from: time))
            #expect(DateTimeUtils.isWindowActive(startHour: 22, startMinute: 0, endHour: 6, endMinute: 0, days: [6], now: fall, calendar: cal))
        }
    }
}
