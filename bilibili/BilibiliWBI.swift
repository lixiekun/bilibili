import Foundation
import SwiftyJSON
import CryptoKit

/// 生成 B 站 WBI 请求签名的辅助工具。
struct BilibiliWBI {
    private static let mixinKeyTable: [Int] = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 52, 20, 34, 44, 38]

    private var mixinKey: String?

    mutating func ensureKey() async throws {
        if mixinKey != nil { return }
        let key = try await fetchMixinKey()
        mixinKey = key
    }

    mutating func sign(params: [String: String]) async throws -> [String: String] {
        try await ensureKey()
        guard let mixinKey else { return params }

        let wts = Int(Date().timeIntervalSince1970)
        var filtered = params.filter { key, _ in key != "w_rid" && key != "wts" }
        filtered["wts"] = "\(wts)"

        let sorted = filtered.sorted { $0.key < $1.key }
        let paramString = sorted.map { key, value in
            let escaped = value.replacingOccurrences(of: " ", with: "+")
            return "\(key)=\(escaped)"
        }.joined(separator: "&")

        let signInput = paramString + mixinKey
        let md5 = Insecure.MD5.hash(data: Data(signInput.utf8)).map { String(format: "%02x", $0) }.joined()

        var signed = filtered
        signed["w_rid"] = md5
        return signed
    }

    private func fetchMixinKey() async throws -> String {
        let url = URL(string: "https://api.bilibili.com/x/web-interface/nav")!
        var request = URLRequest(url: url)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let header = HTTPCookie.requestHeaderFields(with: cookies)
        header.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSON(data: data)
        let imgURL = json["data"]["wbi_img"]["img_url"].stringValue
        let subURL = json["data"]["wbi_img"]["sub_url"].stringValue

        let imgKey = URL(string: imgURL)?.lastPathComponent.components(separatedBy: ".").first ?? ""
        let subKey = URL(string: subURL)?.lastPathComponent.components(separatedBy: ".").first ?? ""
        let raw = imgKey + subKey
        let arr = Array(raw)
        let key = String(Self.mixinKeyTable.compactMap { idx in
            guard idx < arr.count else { return nil }
            return arr[idx]
        })
        return String(key.prefix(32))
    }
}
