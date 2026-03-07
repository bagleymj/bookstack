import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case notFound
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Please sign in again."
        case .notFound: return "Resource not found."
        case .serverError(let msg): return msg
        case .networkError(let err): return err.localizedDescription
        case .decodingError(let err): return "Data error: \(err.localizedDescription)"
        case .invalidURL: return "Invalid URL."
        }
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

final class APIClient {
    static let shared = APIClient()

    #if DEBUG
    var baseURL = "http://localhost:3000"
    #else
    var baseURL = "https://bookstack.fly.dev"
    #endif

    private let session: URLSession
    private let decoder: JSONDecoder

    var onUnauthorized: (() -> Void)?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws -> AuthResponse {
        let body = ["user": ["email": email, "password": password]]
        let response: AuthResponse = try await request(.post, "/api/v1/auth/sign_in", body: body, authenticated: false)
        KeychainManager.shared.token = response.token
        return response
    }

    func signUp(email: String, password: String, passwordConfirmation: String, name: String?) async throws -> AuthResponse {
        var userParams: [String: String] = [
            "email": email,
            "password": password,
            "password_confirmation": passwordConfirmation
        ]
        if let name = name { userParams["name"] = name }
        let body = ["user": userParams]
        let response: AuthResponse = try await request(.post, "/api/v1/auth/sign_up", body: body, authenticated: false)
        KeychainManager.shared.token = response.token
        return response
    }

    func signOut() async throws {
        let _: [String: String] = try await request(.delete, "/api/v1/auth/sign_out")
        KeychainManager.shared.clearAll()
    }

    // MARK: - Dashboard

    func fetchDashboard() async throws -> DashboardResponse {
        try await request(.get, "/api/v1/dashboard")
    }

    // MARK: - Books

    func fetchBooks(status: String? = nil) async throws -> BooksResponse {
        var path = "/api/v1/books"
        if let status = status { path += "?status=\(status)" }
        return try await request(.get, path)
    }

    func fetchBook(id: Int) async throws -> BookDetailResponse {
        try await request(.get, "/api/v1/books/\(id)")
    }

    func createBook(_ params: BookCreateParams) async throws -> BookResponse {
        try await request(.post, "/api/v1/books", body: ["book": params])
    }

    func updateBook(id: Int, params: [String: Any]) async throws -> BookResponse {
        try await request(.patch, "/api/v1/books/\(id)", body: ["book": params])
    }

    func deleteBook(id: Int) async throws {
        let _: EmptyResponse = try await request(.delete, "/api/v1/books/\(id)")
    }

    func startReading(bookId: Int) async throws -> BookResponse {
        try await request(.post, "/api/v1/books/\(bookId)/start_reading")
    }

    func markBookCompleted(bookId: Int) async throws -> BookResponse {
        try await request(.post, "/api/v1/books/\(bookId)/mark_completed")
    }

    func updateProgress(bookId: Int, currentPage: Int) async throws -> BookResponse {
        try await request(.post, "/api/v1/books/\(bookId)/update_progress", body: ["current_page": currentPage])
    }

    // MARK: - Reading Sessions

    func fetchSessions(limit: Int = 20) async throws -> ReadingSessionsResponse {
        try await request(.get, "/api/v1/reading_sessions?limit=\(limit)")
    }

    func fetchActiveSession() async throws -> ReadingSessionResponse {
        try await request(.get, "/api/v1/reading_sessions/active")
    }

    func startSession(bookId: Int, startPage: Int? = nil) async throws -> ReadingSessionResponse {
        var body: [String: Any] = ["book_id": bookId]
        if let startPage = startPage { body["start_page"] = startPage }
        return try await request(.post, "/api/v1/reading_sessions/start", body: body)
    }

    func stopSession(id: Int) async throws -> ReadingSessionResponse {
        try await request(.post, "/api/v1/reading_sessions/\(id)/stop")
    }

    func completeSession(id: Int, endPage: Int) async throws -> ReadingSessionResponse {
        try await request(.post, "/api/v1/reading_sessions/\(id)/complete", body: ["end_page": endPage])
    }

    func createManualSession(bookId: Int, startPage: Int, endPage: Int, durationSeconds: Int) async throws -> ReadingSessionResponse {
        try await request(.post, "/api/v1/reading_sessions", body: [
            "book_id": bookId,
            "start_page": startPage,
            "end_page": endPage,
            "duration_seconds": durationSeconds,
            "untracked": true
        ])
    }

    func deleteSession(id: Int) async throws {
        let _: EmptyResponse = try await request(.delete, "/api/v1/reading_sessions/\(id)")
    }

    // MARK: - Reading Goals

    func fetchGoals(status: String? = nil) async throws -> ReadingGoalsResponse {
        var path = "/api/v1/reading_goals"
        if let status = status { path += "?status=\(status)" }
        return try await request(.get, path)
    }

    func fetchGoal(id: Int) async throws -> ReadingGoalResponse {
        try await request(.get, "/api/v1/reading_goals/\(id)")
    }

    func createGoal(bookId: Int, startedOn: String, targetDate: String, includeWeekends: Bool) async throws -> ReadingGoalResponse {
        try await request(.post, "/api/v1/reading_goals", body: [
            "reading_goal": [
                "book_id": bookId,
                "started_on": startedOn,
                "target_completion_date": targetDate,
                "include_weekends": includeWeekends
            ] as [String: Any]
        ])
    }

    func markGoalCompleted(id: Int) async throws -> ReadingGoalResponse {
        try await request(.post, "/api/v1/reading_goals/\(id)/mark_completed")
    }

    func markGoalAbandoned(id: Int) async throws -> ReadingGoalResponse {
        try await request(.post, "/api/v1/reading_goals/\(id)/mark_abandoned")
    }

    func redistributeGoal(id: Int) async throws -> ReadingGoalResponse {
        try await request(.post, "/api/v1/reading_goals/\(id)/redistribute")
    }

    func catchUpGoal(id: Int) async throws -> ReadingGoalResponse {
        try await request(.post, "/api/v1/reading_goals/\(id)/catch_up")
    }

    func resolveDiscrepancy(goalId: Int, strategy: String) async throws -> ReadingGoalResponse {
        try await request(.post, "/api/v1/reading_goals/\(goalId)/resolve_discrepancy", body: ["strategy": strategy])
    }

    // MARK: - Profile

    func fetchProfile() async throws -> ProfileResponse {
        try await request(.get, "/api/v1/profile")
    }

    func updateProfile(params: [String: Any]) async throws -> ProfileResponse {
        try await request(.patch, "/api/v1/profile", body: ["profile": params])
    }

    // MARK: - Pipeline

    func fetchPipeline() async throws -> PipelineResponse {
        try await request(.get, "/api/v1/pipeline")
    }

    // MARK: - Daily Quotas

    func recordPages(quotaId: Int, pages: Int) async throws -> DailyQuotaResponse {
        try await request(.patch, "/api/v1/daily_quotas/\(quotaId)", body: ["actual_pages": pages])
    }

    // MARK: - Generic Request

    private func request<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Any? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated, let token = KeychainManager.shared.token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            if let encodable = body as? Encodable {
                urlRequest.httpBody = try JSONEncoder().encode(AnyEncodable(encodable))
            } else {
                urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self, data.isEmpty || httpResponse.statusCode == 204 {
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            await MainActor.run { onUnauthorized?() }
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.message)
            }
            throw APIError.serverError("Server error (\(httpResponse.statusCode))")
        }
    }
}

struct EmptyResponse: Decodable {}

// Type-erasing wrapper for Encodable
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
