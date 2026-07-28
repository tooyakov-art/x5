import Foundation

struct ProfileFollowCounts: Equatable, Sendable {
    var followers: Int
    var following: Int
}

enum ProfileFollowServiceError: Error, Equatable {
    case invalidRequest
    case http(statusCode: Int)
}

struct ProfileFollowService {
    private enum Dimension: String {
        // A profile's followers are rows where that profile is being followed.
        case followers = "following_id"
        // A profile's following are rows created by that profile.
        case following = "follower_id"
    }

    private struct FollowRow: Decodable {
        let followerId: String

        enum CodingKeys: String, CodingKey {
            case followerId = "follower_id"
        }
    }

    private let session: URLSession
    private let baseURL: URL
    private let anonKey: String

    init(
        session: URLSession = .shared,
        baseURL: URL = X5Config.supabaseBaseURL,
        anonKey: String = X5Config.supabaseAnonKey
    ) {
        self.session = session
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

    func loadCounts(
        userId: String,
        accessToken: String?
    ) async throws -> ProfileFollowCounts {
        let followers = try await count(
            .followers,
            userId: userId,
            accessToken: accessToken
        )
        let following = try await count(
            .following,
            userId: userId,
            accessToken: accessToken
        )
        return ProfileFollowCounts(followers: followers, following: following)
    }

    private func count(
        _ dimension: Dimension,
        userId: String,
        accessToken: String?
    ) async throws -> Int {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/followers"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ProfileFollowServiceError.invalidRequest
        }
        components.queryItems = [
            URLQueryItem(name: dimension.rawValue, value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "follower_id")
        ]
        guard let url = components.url else {
            throw ProfileFollowServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        if let accessToken, !accessToken.isEmpty {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw ProfileFollowServiceError.http(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }

        if let range = http.value(forHTTPHeaderField: "Content-Range"),
           let total = range.split(separator: "/").last.map(String.init),
           let count = Int(total) {
            return count
        }

        return (try? JSONDecoder().decode([FollowRow].self, from: data).count) ?? 0
    }
}

extension Notification.Name {
    static let x5FollowStateDidChange = Notification.Name("x5.follow.state.did_change")
}
