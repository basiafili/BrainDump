import Foundation
import Observation
import Testing

nonisolated enum InjectedSaveError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "Injected save failure." }
}

actor ControlledCaptureWriter: CaptureWriting {
    private(set) var requests: [CaptureWriteRequest] = []
    private var pending: [Int: CheckedContinuation<CaptureWriteOutcome, any Error>] = [:]
    private var observers: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private let automatic: Bool
    private let failureIndices: Set<Int>

    init(automatic: Bool = true, failureIndices: Set<Int> = []) {
        self.automatic = automatic
        self.failureIndices = failureIndices
    }
    var requestCount: Int { requests.count }

    func save(_ request: CaptureWriteRequest) async throws -> CaptureWriteOutcome {
        let index = requests.count
        requests.append(request)
        if automatic {
            notifyObservers()
            if failureIndices.contains(index) { throw InjectedSaveError.failed }
            return receipt(index)
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            notifyObservers()
        }
    }

    func waitForCall(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { observers[count, default: []].append($0) }
    }

    func succeed(_ index: Int, asCopy: Bool = false) {
        guard let continuation = pending.removeValue(forKey: index) else { preconditionFailure("No pending save at index \(index)") }
        continuation.resume(returning: receipt(index, asCopy: asCopy))
    }
    func fail(_ index: Int) {
        guard let continuation = pending.removeValue(forKey: index) else { preconditionFailure("No pending save at index \(index)") }
        continuation.resume(throwing: InjectedSaveError.failed)
    }

    private func receipt(_ index: Int, asCopy: Bool = false) -> CaptureWriteOutcome {
        let request = requests[index]
        if request.isEmpty { return .empty }
        let date = request.binding?.firstSavedAt ?? Date(timeIntervalSince1970: 1_700_000_000)
        let folder = request.binding?.folder ?? request.projectFolder
        let naming = CaptureNaming(firstSavedAt: date)
        let newURL = folder.url.appendingPathComponent(naming.monthFolder).appendingPathComponent(naming.filename(suffix: UInt(index)))
        let url = asCopy ? folder.url.appendingPathComponent(naming.monthFolder).appendingPathComponent(naming.filename(suffix: UInt(index + 1)))
            : request.binding?.fileURL ?? newURL
        return .saved(CaptureBinding(folder: folder, fileURL: url, firstSavedAt: date, baseline: Data(request.text.utf8)))
    }

    private func notifyObservers() {
        let ready = observers.keys.filter { $0 <= requests.count }
        for count in ready {
            observers.removeValue(forKey: count)?.forEach { $0.resume() }
        }
    }
}

@MainActor
struct CoordinatorFixture {
    let suite: String
    let defaults: UserDefaults
    let folders: TestFolderAuthorization
    let projects: ProjectStore
    let first: ProjectRecord
    let second: ProjectRecord
    let writer: ControlledCaptureWriter
    let coordinator: EditorCoordinator

    static func make(automatic: Bool = true, failureIndices: Set<Int> = []) async throws -> Self {
        let suite = "BrainDumpCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let folders = TestFolderAuthorization()
        let projects = try ProjectStore(defaults: defaults, folders: folders)
        let first = try await projects.register(name: "First", selectedFolder: URL(fileURLWithPath: "/fixtures/first"))
        let second = try await projects.register(name: "Second", selectedFolder: URL(fileURLWithPath: "/fixtures/second"))
        let writer = ControlledCaptureWriter(automatic: automatic, failureIndices: failureIndices)
        return Self(suite: suite, defaults: defaults, folders: folders, projects: projects, first: first, second: second,
                    writer: writer, coordinator: EditorCoordinator(projects: projects, writer: writer))
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite) }
    func openFirst() async throws -> EditorSession { try await coordinator.registerWindow(for: first.id) }
}

/// Observe one-shot changes instead of polling/yielding/sleeping to guess when a
/// command has been accepted. All predicate reads occur on the owning actor.
@MainActor
func waitUntilObserved(_ predicate: @escaping @MainActor () -> Bool) async {
    while !predicate() {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking { _ = predicate() } onChange: { continuation.resume() }
        }
    }
}

nonisolated extension EditorSaveOutcome {
    var savedBinding: CaptureBinding? {
        if case .saved(let binding) = self { return binding }
        return nil
    }
    var isFailure: Bool { if case .failed = self { return true }; return false }
}
nonisolated extension EditorOperationOutcome {
    var isFailure: Bool { if case .failed = self { return true }; return false }
    var windowIDs: [UUID]? { if case .closeWindows(let ids) = self { return ids }; return nil }
}
