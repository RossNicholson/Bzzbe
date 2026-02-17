import Foundation

struct ScheduledTaskSchedule: Codable, Equatable {
    enum Kind: String, Codable {
        case oneShot
        case recurring
    }

    let kind: Kind
    let intervalMinutes: Int?

    static var oneShot: ScheduledTaskSchedule {
        ScheduledTaskSchedule(kind: .oneShot, intervalMinutes: nil)
    }

    static func recurring(every intervalMinutes: Int) -> ScheduledTaskSchedule {
        ScheduledTaskSchedule(kind: .recurring, intervalMinutes: max(1, intervalMinutes))
    }
}

struct ScheduledTaskJob: Codable, Equatable, Identifiable {
    let id: UUID
    let taskID: String
    let taskName: String
    let input: String
    let schedule: ScheduledTaskSchedule
    var nextRunAt: Date
    var retryCount: Int
    let maxRetryCount: Int
}

enum ScheduledTaskRunStatus: String, Codable, Equatable {
    case completed
    case failed
}

struct ScheduledTaskRunLog: Codable, Equatable, Identifiable {
    let id: UUID
    let jobID: UUID
    let taskID: String
    let taskName: String
    let status: ScheduledTaskRunStatus
    let timestamp: Date
    let message: String?
}

struct ScheduledTaskState: Codable, Equatable {
    var jobs: [ScheduledTaskJob]
    var logs: [ScheduledTaskRunLog]

    static let empty = ScheduledTaskState(jobs: [], logs: [])
}

protocol ScheduledTaskStateStoring {
    func loadState() throws -> ScheduledTaskState
    func saveState(_ state: ScheduledTaskState) throws
}

enum ScheduledTaskStoreError: Error {
    case failedToCreateDirectory
}

struct JSONScheduledTaskStateStore: ScheduledTaskStateStoring {
    let fileURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.decoder = decoder
        self.encoder = encoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    static func defaultStore(fileManager: FileManager = .default) -> JSONScheduledTaskStateStore {
        let appSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let appDirectory = appSupportRoot.appendingPathComponent("Bzzbe", isDirectory: true)
        let fileURL = appDirectory.appendingPathComponent("scheduled_tasks.json", isDirectory: false)
        return JSONScheduledTaskStateStore(fileURL: fileURL, fileManager: fileManager)
    }

    func loadState() throws -> ScheduledTaskState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ScheduledTaskState.self, from: data)
    }

    func saveState(_ state: ScheduledTaskState) throws {
        guard ensureDirectoryExists() else {
            throw ScheduledTaskStoreError.failedToCreateDirectory
        }
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureDirectoryExists() -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}

protocol ScheduledTaskScheduling {
    func jobs() -> [ScheduledTaskJob]
    func logs() -> [ScheduledTaskRunLog]
    func scheduleOneShot(taskID: String, taskName: String, input: String, runAt: Date) throws
    func scheduleRecurring(taskID: String, taskName: String, input: String, intervalMinutes: Int, firstRunAt: Date) throws
    func removeJob(jobID: UUID) throws
    func dueJobs(at: Date) -> [ScheduledTaskJob]
    func recordRunResult(jobID: UUID, status: ScheduledTaskRunStatus, message: String?, at: Date) throws
}

final class JSONScheduledTaskScheduler: ScheduledTaskScheduling {
    private let stateStore: ScheduledTaskStateStoring
    private var state: ScheduledTaskState

    init(stateStore: ScheduledTaskStateStoring = JSONScheduledTaskStateStore.defaultStore()) {
        self.stateStore = stateStore
        self.state = (try? stateStore.loadState()) ?? .empty
    }

    func jobs() -> [ScheduledTaskJob] {
        state.jobs.sorted { lhs, rhs in
            lhs.nextRunAt < rhs.nextRunAt
        }
    }

    func logs() -> [ScheduledTaskRunLog] {
        state.logs.sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }

    func scheduleOneShot(taskID: String, taskName: String, input: String, runAt: Date) throws {
        let job = ScheduledTaskJob(
            id: UUID(),
            taskID: taskID,
            taskName: taskName,
            input: input,
            schedule: .oneShot,
            nextRunAt: runAt,
            retryCount: 0,
            maxRetryCount: 2
        )
        state.jobs.append(job)
        try persist()
    }

    func scheduleRecurring(taskID: String, taskName: String, input: String, intervalMinutes: Int, firstRunAt: Date) throws {
        let interval = max(1, intervalMinutes)
        let job = ScheduledTaskJob(
            id: UUID(),
            taskID: taskID,
            taskName: taskName,
            input: input,
            schedule: .recurring(every: interval),
            nextRunAt: firstRunAt,
            retryCount: 0,
            maxRetryCount: 2
        )
        state.jobs.append(job)
        try persist()
    }

    func removeJob(jobID: UUID) throws {
        state.jobs.removeAll { $0.id == jobID }
        try persist()
    }

    func dueJobs(at: Date) -> [ScheduledTaskJob] {
        jobs().filter { $0.nextRunAt <= at }
    }

    func recordRunResult(jobID: UUID, status: ScheduledTaskRunStatus, message: String?, at: Date) throws {
        guard let index = state.jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }
        var job = state.jobs[index]
        state.logs.insert(
            ScheduledTaskRunLog(
                id: UUID(),
                jobID: job.id,
                taskID: job.taskID,
                taskName: job.taskName,
                status: status,
                timestamp: at,
                message: message
            ),
            at: 0
        )
        if state.logs.count > 200 {
            state.logs = Array(state.logs.prefix(200))
        }

        switch status {
        case .completed:
            job.retryCount = 0
            if job.schedule.kind == .oneShot {
                state.jobs.remove(at: index)
            } else if let intervalMinutes = job.schedule.intervalMinutes {
                job.nextRunAt = at.addingTimeInterval(TimeInterval(intervalMinutes * 60))
                state.jobs[index] = job
            }
        case .failed:
            if job.retryCount < job.maxRetryCount {
                job.retryCount += 1
                let retryDelay = TimeInterval(30 * job.retryCount)
                job.nextRunAt = at.addingTimeInterval(retryDelay)
                state.jobs[index] = job
            } else if job.schedule.kind == .oneShot {
                state.jobs.remove(at: index)
            } else if let intervalMinutes = job.schedule.intervalMinutes {
                job.retryCount = 0
                job.nextRunAt = at.addingTimeInterval(TimeInterval(intervalMinutes * 60))
                state.jobs[index] = job
            }
        }

        try persist()
    }

    private func persist() throws {
        try stateStore.saveState(state)
    }
}
