import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import R2DCore

public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST" }
public struct HTTPRequest: Sendable { public let path: String, method: HTTPMethod, headers: [String: String], body: Data?, timeout: TimeInterval; public init(path: String, method: HTTPMethod, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 30) { self.path = path; self.method = method; self.headers = headers; self.body = body; self.timeout = timeout } }
public struct HTTPResponse: Sendable { public let statusCode: Int, headers: [String: String], body: Data; public init(statusCode: Int, headers: [String: String], body: Data) { self.statusCode = statusCode; self.headers = headers; self.body = body } }
public protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> HTTPResponse }

public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do { let (data, response) = try await session.data(for: request); guard let http = response as? HTTPURLResponse else { throw TelemetryUploadError.invalidResponse }; return .init(statusCode: http.statusCode, headers: http.allHeaderFields.reduce(into: [:]) { $0[String(describing: $1.key)] = String(describing: $1.value) }, body: data) }
        catch let error as URLError { if error.code == .timedOut { throw TelemetryUploadError.timeout }; if [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost].contains(error.code) { throw TelemetryUploadError.offline }; throw TelemetryUploadError.invalidResponse }
    }
}

public struct HTTPClient: Sendable {
    public let baseURL: URL
    private let transport: HTTPTransport
    private let tokenProvider: TokenProvider?
    public init(baseURL: URL, transport: HTTPTransport, tokenProvider: TokenProvider? = nil) { self.baseURL = baseURL; self.transport = transport; self.tokenProvider = tokenProvider }
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await send(request, allowingStatusCodes: [])
    }
    public func send(_ request: HTTPRequest, allowingStatusCodes: Set<Int>) async throws -> HTTPResponse {
        let originalToken = try await tokenProvider?.accessToken()
        let response = try await execute(request, token: originalToken)
        if response.statusCode == 401, let tokenProvider {
            let currentToken = try await tokenProvider.accessToken()
            let retryToken = currentToken != originalToken ? currentToken : try await tokenProvider.refreshAccessToken()
            let retry = try await execute(request, token: retryToken)
            if !allowingStatusCodes.contains(retry.statusCode) { try classify(retry) }
            return retry
        }
        if !allowingStatusCodes.contains(response.statusCode) { try classify(response) }
        return response
    }
    private func execute(_ request: HTTPRequest, token: String?) async throws -> HTTPResponse {
        guard let url = URL(string: request.path, relativeTo: baseURL) else { throw TelemetryUploadError.invalidResponse }
        var value = URLRequest(url: url, timeoutInterval: request.timeout); value.httpMethod = request.method.rawValue; value.httpBody = request.body; request.headers.forEach { value.setValue($1, forHTTPHeaderField: $0) }
        if let token { value.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return try await transport.send(value)
    }
    private func classify(_ response: HTTPResponse) throws {
        switch response.statusCode { case 200..<300: return; case 400: throw TelemetryUploadError.validationFailed(code: decodeCode(response.body) ?? "validation_error"); case 401: throw TelemetryUploadError.unauthorized; case 403: throw TelemetryUploadError.forbidden; case 429: throw TelemetryUploadError.rateLimited(retryAfter: response.headers.first { $0.key.lowercased() == "retry-after" }.flatMap { TimeInterval($0.value) }); case 500...599: throw TelemetryUploadError.serverFailure(statusCode: response.statusCode); default: throw TelemetryUploadError.permanentRejection(code: decodeCode(response.body) ?? "http_\(response.statusCode)") }
    }
    private func decodeCode(_ data: Data) -> String? { (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String }
}
