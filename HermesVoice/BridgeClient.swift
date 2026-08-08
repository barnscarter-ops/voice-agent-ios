import Foundation

/// Talks to the Voice-Agent bridge over the tailnet.
///
/// The bearer token is passed straight from the Keychain into a header and is
/// never logged, never put in a URL, and never included in an error message.
struct BridgeClient {
    let baseURL: URL
    let token: String

    /// A whole turn is slow by nature: speech-to-text, then the model, then
    /// speech synthesis. Measured warm turns are ~7 s and a cold one (first
    /// request after the bridge restarts, which loads the STT model) has been
    /// seen at 42 s, so the ceiling is generous. A *connection* failure still
    /// surfaces immediately — that timeout is not what this bounds.
    private static let turnTimeout: TimeInterval = 120

    /// Reachability has to answer fast or it is useless as a "is Tailscale on?"
    /// check — the user is staring at the screen waiting for it.
    private static let probeTimeout: TimeInterval = 5

    private static func session(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        // Without this, URLSession parks the request until connectivity appears
        // instead of failing — which is exactly the hang we must not have when
        // Tailscale is off.
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: - Reachability

    /// `GET /health`. Deliberately unauthenticated on the bridge side, so this
    /// answers "can I reach it at all" without involving the token.
    func checkHealth() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await perform(request, timeout: Self.probeTimeout)
        guard let http = response as? HTTPURLResponse else {
            throw TurnFailure.badResponse("no HTTP response from /health")
        }
        guard http.statusCode == 200 else {
            throw TurnFailure.rejected(BridgeFailure.parse(status: http.statusCode, body: data))
        }
    }

    /// `POST /converse` — the clip goes up, transcript + reply + speech come back.
    func converse(clip: Data, filename: String, sessionID: String, target: String) async throws -> ConverseResponse {
        let boundary = "hermes-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("converse"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            fields: ["session_id": sessionID, "target": target],
            fileField: "audio",
            filename: filename,
            fileData: clip,
            mimeType: "audio/m4a"
        )

        let (data, response) = try await perform(request, timeout: Self.turnTimeout)
        guard let http = response as? HTTPURLResponse else {
            throw TurnFailure.badResponse("no HTTP response from /converse")
        }
        if http.statusCode == 401 {
            throw TurnFailure.unauthorized
        }
        guard http.statusCode == 200 else {
            throw TurnFailure.rejected(BridgeFailure.parse(status: http.statusCode, body: data))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(ConverseResponse.self, from: data)
        } catch {
            throw TurnFailure.badResponse("couldn't read the bridge's reply: \(error.localizedDescription)")
        }
    }

    // MARK: - Plumbing

    private func perform(_ request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        do {
            return try await Self.session(timeout: timeout).data(for: request)
        } catch let urlError as URLError {
            // A cancelled request is the user pressing stop, not a fault.
            if urlError.code == .cancelled { throw CancellationError() }
            throw TurnFailure.from(urlError: urlError)
        }
    }

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        filename: String,
        fileData: Data,
        mimeType: String
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
