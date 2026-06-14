import XCTest
@testable import Funke

/// Tests für `NoteResponseParser`: tolerant gegenüber Code-Fences und Prosa,
/// Titel ist Pflicht, fehlender Body fällt auf den Titel zurück.
final class NoteEnrichmentTests: XCTestCase {

    func testParserCleanJSON() throws {
        let raw = #"{"title": "Einkauf", "body": "Milch und Brot kaufen."}"#
        let suggestion = try NoteResponseParser.parse(raw)
        XCTAssertEqual(suggestion.title, "Einkauf")
        XCTAssertEqual(suggestion.body, "Milch und Brot kaufen.")
    }

    func testParserCodeFences() throws {
        let raw = """
        ```json
        {"title": "Meeting-Notizen", "body": "- Punkt A\\n- Punkt B"}
        ```
        """
        let suggestion = try NoteResponseParser.parse(raw)
        XCTAssertEqual(suggestion.title, "Meeting-Notizen")
        XCTAssertEqual(suggestion.body, "- Punkt A\n- Punkt B")
    }

    func testParserSurroundingProse() throws {
        let raw = """
        Hier deine bereinigte Notiz:
        {"title": "Idee", "body": "Funke um Sprachnotizen erweitern."}
        Fertig!
        """
        let suggestion = try NoteResponseParser.parse(raw)
        XCTAssertEqual(suggestion.title, "Idee")
        XCTAssertEqual(suggestion.body, "Funke um Sprachnotizen erweitern.")
    }

    func testParserMissingTitleThrows() {
        let raw = #"{"body": "Nur ein Body, kein Titel."}"#
        XCTAssertThrowsError(try NoteResponseParser.parse(raw)) { error in
            guard case EnrichmentError.invalidResponse = error else {
                return XCTFail("Erwartete .invalidResponse, bekam \(error)")
            }
        }
    }

    func testParserEmptyTitleThrows() {
        let raw = #"{"title": "   ", "body": "Etwas"}"#
        XCTAssertThrowsError(try NoteResponseParser.parse(raw)) { error in
            guard case EnrichmentError.invalidResponse = error else {
                return XCTFail("Erwartete .invalidResponse, bekam \(error)")
            }
        }
    }

    func testParserMissingBodyFallsBackToTitle() throws {
        let raw = #"{"title": "Nur Titel"}"#
        let suggestion = try NoteResponseParser.parse(raw)
        XCTAssertEqual(suggestion.title, "Nur Titel")
        XCTAssertEqual(suggestion.body, "Nur Titel", "Fehlender Body fällt auf den Titel zurück")
    }

    func testParserEmptyBodyFallsBackToTitle() throws {
        let raw = #"{"title": "Titel", "body": ""}"#
        let suggestion = try NoteResponseParser.parse(raw)
        XCTAssertEqual(suggestion.body, "Titel", "Leerer Body fällt auf den Titel zurück")
    }

    func testParserNoJSONThrows() {
        let raw = "Hier ist überhaupt kein JSON-Objekt."
        XCTAssertThrowsError(try NoteResponseParser.parse(raw)) { error in
            guard case EnrichmentError.invalidResponse = error else {
                return XCTFail("Erwartete .invalidResponse, bekam \(error)")
            }
        }
    }
}
