#if canImport(SwiftUI)
@testable import BzzbeApp
import Foundation
import Testing

@Test("JSONScheduledTaskScheduler persists scheduled jobs")
func jsonScheduledTaskSchedulerPersistsJobs() throws {
    let store = InMemoryScheduledTaskStateStore()
    let scheduler = JSONScheduledTaskScheduler(stateStore: store)
    let now = Date(timeIntervalSince1970: 1_000)

    try scheduler.scheduleOneShot(
        taskID: "summarize",
        taskName: "Summarize Text",
        input: "input-1",
        runAt: now
    )
    try scheduler.scheduleRecurring(
        taskID: "rewrite_tone",
        taskName: "Rewrite for Tone",
        input: "input-2",
        intervalMinutes: 30,
        firstRunAt: now
    )

    let restored = JSONScheduledTaskScheduler(stateStore: store)
    let jobs = restored.jobs()

    #expect(jobs.count == 2)
    #expect(jobs.contains(where: { $0.schedule.kind == .oneShot }))
    #expect(jobs.contains(where: { $0.schedule.kind == .recurring }))
}

@Test("JSONScheduledTaskScheduler retries failed one-shot jobs then removes them")
func jsonScheduledTaskSchedulerRetriesAndRemovesOneShotJobs() throws {
    let store = InMemoryScheduledTaskStateStore()
    let scheduler = JSONScheduledTaskScheduler(stateStore: store)
    let now = Date(timeIntervalSince1970: 2_000)

    try scheduler.scheduleOneShot(
        taskID: "summarize",
        taskName: "Summarize Text",
        input: "input",
        runAt: now
    )
    guard let jobID = scheduler.jobs().first?.id else {
        Issue.record("Expected scheduled job")
        return
    }

    try scheduler.recordRunResult(jobID: jobID, status: .failed, message: "first", at: now)
    #expect(scheduler.jobs().first?.retryCount == 1)

    try scheduler.recordRunResult(jobID: jobID, status: .failed, message: "second", at: now.addingTimeInterval(30))
    #expect(scheduler.jobs().first?.retryCount == 2)

    try scheduler.recordRunResult(jobID: jobID, status: .failed, message: "third", at: now.addingTimeInterval(90))
    #expect(scheduler.jobs().isEmpty)
    #expect(scheduler.logs().count == 3)
}

@Test("JSONScheduledTaskScheduler reschedules recurring jobs after completion")
func jsonScheduledTaskSchedulerReschedulesRecurringJobs() throws {
    let store = InMemoryScheduledTaskStateStore()
    let scheduler = JSONScheduledTaskScheduler(stateStore: store)
    let now = Date(timeIntervalSince1970: 3_000)

    try scheduler.scheduleRecurring(
        taskID: "summarize",
        taskName: "Summarize Text",
        input: "input",
        intervalMinutes: 15,
        firstRunAt: now
    )
    guard let jobID = scheduler.jobs().first?.id else {
        Issue.record("Expected scheduled recurring job")
        return
    }

    try scheduler.recordRunResult(jobID: jobID, status: .completed, message: nil, at: now)

    guard let updated = scheduler.jobs().first else {
        Issue.record("Expected recurring job to remain scheduled")
        return
    }
    #expect(updated.retryCount == 0)
    #expect(updated.nextRunAt == now.addingTimeInterval(15 * 60))
    #expect(scheduler.logs().first?.status == .completed)
}

private final class InMemoryScheduledTaskStateStore: ScheduledTaskStateStoring {
    private var state: ScheduledTaskState = .empty

    func loadState() throws -> ScheduledTaskState {
        state
    }

    func saveState(_ state: ScheduledTaskState) throws {
        self.state = state
    }
}
#endif
