import Foundation

struct BilibiliPlayerService {
    struct PlayInfo {
        let url: URL
    }

    enum PlayerError: Error {
        case missingCID
        case noPlayableURL
        case badResponse
        case apiError(code: Int, message: String)
    }

    func fetchPlayURL(bvid: String, cid: Int?) async throws -> PlayInfo {
        let resolvedCID: Int
        if let cid {
            resolvedCID = cid
        } else {
            resolvedCID = try await fetchCID(bvid: bvid)
        }

        var components = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        components.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: "\(resolvedCID)"),
            URLQueryItem(name: "fnval", value: "16"), // HLS
            URLQueryItem(name: "fourk", value: "1"),
            URLQueryItem(name: "qn", value: "80")
        ]
        guard let url = components.url else { throw PlayerError.badResponse }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let header = HTTPCookie.requestHeaderFields(with: cookies)
        header.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlayerError.badResponse
        }

        let decoded = try JSONDecoder().decode(PlayResponse.self, from: data)
        if decoded.code != 0 {
            throw PlayerError.apiError(code: decoded.code, message: decoded.message)
        }
        if let urlString = decoded.data.durl.first?.url, let url = URL(string: urlString) {
            return PlayInfo(url: url)
        }
        if let dash = decoded.data.dash,
           let baseURL = dash.video.first?.baseURL,
           let url = URL(string: baseURL) {
            return PlayInfo(url: url)
        }

        throw PlayerError.noPlayableURL
    }

    private func fetchCID(bvid: String) async throws -> Int {
        var components = URLComponents(string: "https://api.bilibili.com/x/player/pagelist")!
        components.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "jsonp", value: "jsonp")
        ]
        guard let url = components.url else { throw PlayerError.badResponse }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let header = HTTPCookie.requestHeaderFields(with: cookies)
        header.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlayerError.badResponse
        }

        let decoded = try JSONDecoder().decode(PageListResponse.self, from: data)
        if decoded.code != 0 { throw PlayerError.apiError(code: decoded.code, message: decoded.message) }
        guard let first = decoded.data.first else { throw PlayerError.missingCID }
        return first.cid
    }
}

private struct PlayResponse: Decodable {
    let code: Int
    let message: String
    let data: DataContainer

    struct DataContainer: Decodable {
        let durl: [Durl]
        let dash: Dash?

        struct Durl: Decodable {
            let url: String
        }

        struct Dash: Decodable {
            let video: [Video]
            struct Video: Decodable {
                let baseURL: String
                enum CodingKeys: String, CodingKey { case baseURL = "baseUrl" }
            }
        }
    }
}

private struct PageListResponse: Decodable {
    let code: Int
    let message: String
    let data: [Page]

    struct Page: Decodable {
        let cid: Int
    }
}
