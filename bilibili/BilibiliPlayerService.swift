import Foundation
import SwiftyJSON
import AVKit

struct BilibiliPlayerService {
    struct PlayInfo {
        let url: URL
    }

    enum PlayerError: Error {
        case missingCID
        case noPlayableURL
        case badResponse
        case apiError(code: Int, message: String)
        case invalidURL
    }

    func fetchPlayURL(bvid: String, cid: Int?) async throws -> PlayInfo {
        let resolvedCID: Int
        if let cid {
            resolvedCID = cid
        } else {
            resolvedCID = try await fetchCID(bvid: bvid)
        }

        var components = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        var signer = BilibiliWBI()
        let signedParams = try await signer.sign(params: [
            "bvid": bvid,
            "cid": "\(resolvedCID)",
            "fnval": "16",
            "fourk": "1",
            "qn": "80"
        ])
        components.queryItems = signedParams.map { URLQueryItem(name: $0.key, value: $0.value) }
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

        let json = try JSON(data: data)
        if json["code"].intValue != 0 {
            throw PlayerError.apiError(code: json["code"].intValue, message: json["message"].stringValue)
        }

        if let urlString = json["data"]["durl"].arrayValue.first?["url"].string, let url = URL(string: urlString) {
            return PlayInfo(url: url)
        }
        if let baseURL = json["data"]["dash"]["video"].arrayValue.first?["baseUrl"].string, let url = URL(string: baseURL) {
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

        let json = try JSON(data: data)
        if json["code"].intValue != 0 {
            throw PlayerError.apiError(code: json["code"].intValue, message: json["message"].stringValue)
        }
        guard let firstCID = json["data"].arrayValue.first?["cid"].int else {
            throw PlayerError.missingCID
        }
        return firstCID
    }
}
