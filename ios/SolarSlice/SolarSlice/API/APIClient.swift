import Foundation

// MARK: - API Errors

enum APIError: Error, LocalizedError {
    case invalidToken
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidToken:         return "Session expired. Please log in again."
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .invalidResponse:     return "Invalid server response."
        case .decodingError(let e): return "Data error: \(e.localizedDescription)"
        case .serverError(let code): return "Server error (\(code))."
        }
    }
}

// MARK: - APIClient

final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://api.allumeenergy.com.au/v2")!
    private let session = URLSession.shared

    private init() {}

    // MARK: Auth

    func login(email: String, password: String) async throws -> LoginResponse {
        let url = baseURL.appendingPathComponent("auth/customer-login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        return try await perform(request, as: LoginResponse.self, requiresAuth: false)
    }

    // MARK: Properties

    func fetchProperties(token: String) async throws -> PropertiesResponse {
        let url = baseURL.appendingPathComponent("consumers/me/properties")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await perform(request, as: PropertiesResponse.self)
    }

    // MARK: Snapshots

    func fetchSnapshots(propertyId: Int, from: Int, to: Int, token: String) async throws -> [Snapshot] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("properties/\(propertyId)/snapshots"),
            resolvingAgainstBaseURL: true
        )!
        components.queryItems = [
            URLQueryItem(name: "type", value: "hourly"),
            URLQueryItem(name: "from", value: "\(from)"),
            URLQueryItem(name: "to", value: "\(to)"),
        ]
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await perform(request, as: [Snapshot].self)
    }

    // MARK: - Private helpers

    private func perform<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        requiresAuth: Bool = true
    ) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw urlError
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw APIError.invalidToken
        default:
            throw APIError.serverError(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
