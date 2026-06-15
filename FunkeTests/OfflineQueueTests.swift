import XCTest
@testable import Funke

final class OfflineQueueTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineQueueTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func task(_ name: String) -> PendingItem { .task(PendingCapture(name: name)) }
    private func taskName(_ item: PendingItem) -> String? {
        if case .task(let t) = item { return t.name }
        return nil
    }

    // MARK: - Tests

    func testEnqueuePersistsAndAllReturnsInOrder() async throws {
        let queue = OfflineQueue(directory: directory)
        try await queue.enqueue(task("Eins"))
        try await queue.enqueue(task("Zwei"))
        try await queue.enqueue(task("Drei"))

        let all = await queue.all()
        XCTAssertEqual(all.compactMap(taskName), ["Eins", "Zwei", "Drei"], "Reihenfolge muss erhalten bleiben.")
        let fileURL = directory.appendingPathComponent("queue.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "queue.json muss persistiert sein.")
    }

    func testQueuesTasksAndNotesTogether() async throws {
        let queue = OfflineQueue(directory: directory)
        try await queue.enqueue(.task(PendingCapture(name: "T")))
        try await queue.enqueue(.note(PendingNote(title: "N", body: "B", folder: "Inbox")))

        let all = await queue.all()
        XCTAssertEqual(all.count, 2)
        if case .note(let note) = all[1] {
            XCTAssertEqual(note.title, "N")
            XCTAssertEqual(note.folder, "Inbox")
        } else {
            XCTFail("Zweites Item muss eine Notiz sein.")
        }
    }

    func testPersistenceAcrossNewInstances() async throws {
        let writer = OfflineQueue(directory: directory)
        let a = PendingItem.task(PendingCapture(name: "A"))
        let b = PendingItem.note(PendingNote(title: "B", body: "x", folder: "Inbox"))
        try await writer.enqueue(a)
        try await writer.enqueue(b)

        let reader = OfflineQueue(directory: directory)
        let loaded = await reader.all()
        XCTAssertEqual(loaded.map(\.id), [a.id, b.id], "Neue Instanz muss persistierte Items in Reihenfolge laden.")
    }

    func testMigratesLegacyPendingCaptureFile() async throws {
        // Vor-v2-Format: reines [PendingCapture]-JSON ohne PendingItem-Wrapper.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        [{"id":"\(UUID().uuidString)","name":"Alt-Task","createdAt":"2026-06-15T14:30:00Z"}]
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("queue.json"))

        let queue = OfflineQueue(directory: directory)
        let all = await queue.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(taskName(all[0]), "Alt-Task", "Alte Datei muss als Task migriert werden.")
    }

    func testRemoveDeletesMatchingItemAndPersists() async throws {
        let queue = OfflineQueue(directory: directory)
        let a = PendingItem.task(PendingCapture(name: "A"))
        let b = PendingItem.task(PendingCapture(name: "B"))
        let c = PendingItem.task(PendingCapture(name: "C"))
        try await queue.enqueue(a)
        try await queue.enqueue(b)
        try await queue.enqueue(c)

        try await queue.remove(id: b.id)

        let remaining = await queue.all()
        XCTAssertEqual(remaining.compactMap(taskName), ["A", "C"], "Nur das gewählte Item darf entfernt werden.")

        let reader = OfflineQueue(directory: directory)
        let reloaded = await reader.all()
        XCTAssertEqual(reloaded.compactMap(taskName), ["A", "C"], "Entfernung muss persistiert sein.")
    }

    func testIsEmptyReflectsState() async throws {
        let queue = OfflineQueue(directory: directory)
        var empty = await queue.isEmpty()
        XCTAssertTrue(empty, "Frische Queue (ohne Datei) muss leer sein.")

        let item = PendingItem.task(PendingCapture(name: "X"))
        try await queue.enqueue(item)
        empty = await queue.isEmpty()
        XCTAssertFalse(empty, "Nach Enqueue darf die Queue nicht leer sein.")

        try await queue.remove(id: item.id)
        empty = await queue.isEmpty()
        XCTAssertTrue(empty, "Nach Entfernen des letzten Items muss die Queue leer sein.")
    }

    func testMissingDirectoryIsTreatedAsEmpty() async throws {
        let queue = OfflineQueue(directory: directory)
        let all = await queue.all()
        XCTAssertTrue(all.isEmpty)
        let empty = await queue.isEmpty()
        XCTAssertTrue(empty)
    }
}
