import Foundation

/// Wiederverwendbarer `URLProtocol`-Stub für die HTTP-Client-Tests.
///
/// Pro Request wird eine vorab eingereihte Antwort `(Data, HTTPURLResponse)`
/// (oder ein `Error`) zurückgegeben. Der zuletzt gesehene `URLRequest` wird
/// festgehalten, damit Tests URL, Header und Body prüfen können.
///
/// Wichtig: `URLSession` verschiebt `httpBody` in `httpBodyStream`, bevor der
/// `URLProtocol` den Request sieht. Deshalb wird der Body hier aus dem Stream
/// gelesen und separat als `lastRequestBody` bereitgestellt – `request.httpBody`
/// ist an dieser Stelle `nil`.
final class StubURLProtocol: URLProtocol {

    // MARK: Eingereihte Antworten

    /// Eine eingereihte Antwort: entweder ein erfolgreiches `(Data, Response)`
    /// oder ein Transportfehler.
    enum Stub {
        case success(data: Data, response: HTTPURLResponse)
        case failure(Error)
    }

    /// FIFO-Queue der Antworten. Jeder Request entnimmt die vorderste.
    private(set) static var queue: [Stub] = []

    /// Der zuletzt vom Stub gesehene Request (ohne aufgelösten Body).
    private(set) static var lastRequest: URLRequest?

    /// Der Body des zuletzt gesehenen Requests, aus dem `httpBodyStream` gelesen.
    private(set) static var lastRequestBody: Data?

    // MARK: Test-Helfer

    /// Setzt sämtlichen Stub-Zustand zurück. In `setUp()`/`tearDown()` aufrufen.
    static func reset() {
        queue.removeAll()
        lastRequest = nil
        lastRequestBody = nil
    }

    /// Reiht eine Erfolgsantwort mit frei wählbarem Statuscode ein.
    static func enqueue(
        statusCode: Int,
        json: String,
        headers: [String: String]? = ["Content-Type": "application/json"]
    ) {
        enqueue(statusCode: statusCode, data: Data(json.utf8), headers: headers)
    }

    /// Reiht eine Erfolgsantwort mit roher `Data` ein.
    static func enqueue(
        statusCode: Int,
        data: Data,
        headers: [String: String]? = ["Content-Type": "application/json"]
    ) {
        // URL ist hier irrelevant; die Response trägt nur Status + Header.
        let url = URL(string: "https://api.clickup.com/api/v2")!
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            fatalError("StubURLProtocol: konnte HTTPURLResponse nicht bauen")
        }
        queue.append(.success(data: data, response: response))
    }

    /// Reiht einen Transportfehler ein.
    static func enqueue(error: Error) {
        queue.append(.failure(error))
    }

    /// Erzeugt eine `URLSession`, die ausschließlich über diesen Stub läuft.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Body aus dem Stream lesen (httpBody ist zu diesem Zeitpunkt nil).
        Self.lastRequest = request
        Self.lastRequestBody = Self.readBody(from: request)

        guard !Self.queue.isEmpty else {
            let error = NSError(
                domain: "StubURLProtocol",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Keine Stub-Antwort eingereiht."]
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        switch Self.queue.removeFirst() {
        case let .success(data, response):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Nichts zu tun – synchrone Auslieferung.
    }

    // MARK: Body-Lesen

    /// Liest den Request-Body, egal ob er als `httpBody` oder (üblich nach
    /// dem URLSession-Durchlauf) als `httpBodyStream` vorliegt.
    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 { return nil }   // Lesefehler
            if read == 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
