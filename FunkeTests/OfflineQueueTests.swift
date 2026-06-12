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

    private func makeCapture(name: String) -> PendingCapture {
        PendingCapture(name: name)
    }

    // MARK: - Tests

    func testEnqueuePersistsAndAllReturnsInOrder() async throws {
        let queue = OfflineQueue(directory: directory)

        let first = makeCapture(name: "Eins")
        let second = makeCapture(name: "Zwei")
        let third = makeCapture(name: "Drei")

        try await queue.enqueue(first)
        try await queue.enqueue(second)
        try await queue.enqueue(third)

        let all = await queue.all()
        XCTAssertEqual(all.map(\.name), ["Eins", "Zwei", "Drei"], "Reihenfolge muss erhalten bleiben.")

        // Datei wurde tatsächlich geschrieben.
        let fileURL = directory.appendingPathComponent("queue.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "queue.json muss persistiert sein.")
    }

    func testPersistenceAcrossNewInstances() async throws {
        let writer = OfflineQueue(directory: directory)
        let a = makeCapture(name: "A")
        let b = makeCapture(name: "B")
        try await writer.enqueue(a)
        try await writer.enqueue(b)

        // Eine FRISCHE Instanz auf demselben Verzeichnis muss die Items von Platte laden.
        let reader = OfflineQueue(directory: directory)
        let loaded = await reader.all()
        XCTAssertEqual(loaded.map(\.id), [a.id, b.id], "Neue Instanz muss persistierte Items in Reihenfolge laden.")
    }

    func testRemoveDeletesMatchingItemAndPersists() async throws {
        let queue = OfflineQueue(directory: directory)
        let a = makeCapture(name: "A")
        let b = makeCapture(name: "B")
        let c = makeCapture(name: "C")
        try await queue.enqueue(a)
        try await queue.enqueue(b)
        try await queue.enqueue(c)

        try await queue.remove(id: b.id)

        let remaining = await queue.all()
        XCTAssertEqual(remaining.map(\.name), ["A", "C"], "Nur das gewählte Item darf entfernt werden.")

        // Persistenz der Entfernung über neue Instanz prüfen.
        let reader = OfflineQueue(directory: directory)
        let reloaded = await reader.all()
        XCTAssertEqual(reloaded.map(\.name), ["A", "C"], "Entfernung muss persistiert sein.")
    }

    func testIsEmptyReflectsState() async throws {
        let queue = OfflineQueue(directory: directory)

        var empty = await queue.isEmpty()
        XCTAssertTrue(empty, "Frische Queue (ohne Datei) muss leer sein.")

        let item = makeCapture(name: "X")
        try await queue.enqueue(item)
        empty = await queue.isEmpty()
        XCTAssertFalse(empty, "Nach Enqueue darf die Queue nicht leer sein.")

        try await queue.remove(id: item.id)
        empty = await queue.isEmpty()
        XCTAssertTrue(empty, "Nach Entfernen des letzten Items muss die Queue leer sein.")
    }

    func testMissingDirectoryIsTreatedAsEmpty() async throws {
        // Verzeichnis existiert noch nicht; all()/isEmpty() dürfen nicht crashen.
        let queue = OfflineQueue(directory: directory)
        let all = await queue.all()
        XCTAssertTrue(all.isEmpty)
        let empty = await queue.isEmpty()
        XCTAssertTrue(empty)
    }
}
