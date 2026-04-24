import Foundation

/// HTTP client for the Anthropic Messages API with SSE streaming.
final class AnthropicClient: Sendable {
    let apiKey: String
    let baseURL: URL

    init(apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    /// Stream a single Messages API request, yielding ``StreamEvent`` values.
    ///
    /// Throws on any HTTP or network error. The caller is responsible for retry logic.
    func stream(request: MessageRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.streamOnce(request: request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func streamOnce(
        request: MessageRequest,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let urlRequest = try buildRequest(request)
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 429 {
            // Emit a rate-limit signal then finish normally (caller decides how to wait)
            continuation.yield(.error(AnthropicAPIError(
                type: "rate_limit_error",
                error: AnthropicAPIError.ErrorDetail(
                    type: "rate_limit_error",
                    message: "Rate limited"
                )
            )))
            return
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            var body = ""
            for try await line in bytes.lines { body += line }
            if let data = body.data(using: .utf8),
               let apiError = try? JSONDecoder().decode(AnthropicAPIError.self, from: data) {
                throw apiError
            }
            throw URLError(.badServerResponse)
        }

        var accumulator = SSELineAccumulator()
        for try await line in bytes.lines {
            if let event = accumulator.feed(line) {
                continuation.yield(event)
            }
        }
    }

    private func buildRequest(_ request: MessageRequest) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("v1/messages")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("claude-agent-sdk-swift/1.0", forHTTPHeaderField: "User-Agent")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        return urlRequest
    }
}
