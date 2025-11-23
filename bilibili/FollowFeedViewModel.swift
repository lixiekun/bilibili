import SwiftUI
import SwiftyJSON
import Alamofire

@MainActor
final class FollowFeedViewModel: ObservableObject {
    @Published var videoItems: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // 使用 polymer 动态接口，需登录 Cookie 才有关注流
    private let feedBaseURL = URL(string: "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config)
    }()
    private var page: Int = 1
    private var hasMore: Bool = true

    func refresh() {
        guard !isLoading else { return }
        page = 1
        hasMore = true
        videoItems.removeAll()
        errorMessage = nil
        fetch()
    }

    func fetch() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                var components = URLComponents(url: feedBaseURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "type", value: "video"),
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "platform", value: "web"),
                    URLQueryItem(name: "timezone_offset", value: "28800")
                ]
                guard let url = components.url else { return }

                let headers: HTTPHeaders = [
                    "Referer": "https://www.bilibili.com",
                    "User-Agent": "Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)"
                ]

                let allCookies = HTTPCookieStorage.shared.cookies ?? []

                let data = try await NetworkClient.shared
                    .request(url, method: .get, headers: headers)
                    .serializingData()
                    .value

                let json = try JSON(data: data)
                #if DEBUG
                let rawPreview = String(data: data, encoding: .utf8) ?? ""
                let cookieString = allCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        print("Follow feed cookies: \(cookieString)")
        print("Follow feed code=\(json["code"].intValue) message=\(json["message"].stringValue) items=\(json["data"]["items"].arrayValue.count)")
        print("Follow feed raw preview: \(rawPreview.prefix(2000))")
        #endif

                if json["code"].intValue != 0 {
                    throw NSError(domain: "FollowFeed", code: json["code"].intValue, userInfo: [NSLocalizedDescriptionKey: json["message"].stringValue])
                }

                let items = json["data"]["items"].arrayValue
                let videos: [VideoItem] = items.compactMap { item in
                    let modules = item["modules"]
                    let authorName = modules["module_author"]["name"].string ?? "未知UP"
                    let major = modules["module_dynamic"]["major"]

                    if major["archive"].dictionary != nil {
                        let archive = major["archive"]
                        let bvid = archive["bvid"].stringValue
                        let title = archive["title"].stringValue
                        guard let coverURL = URL(string: archive["cover"].stringValue) else { return nil }
                        let duration = archive["duration"].int ?? parseDuration(text: archive["durationText"].string)
                        let cid = archive["cid"].int
                        let plays = archive["stat"]["play"].int ?? 0
                        return VideoItem(id: bvid, title: title, coverImageURL: coverURL, authorName: authorName, viewCount: plays, duration: duration, cid: cid)
                    } else if major["pgc"].dictionary != nil {
                        let pgc = major["pgc"]
                        let bvid = pgc["bvid"].string ?? UUID().uuidString
                        let title = pgc["title"].string ?? pgc["ep_title"].string ?? "PGC"
                        guard let coverURL = URL(string: pgc["cover"].stringValue) else { return nil }
                        let duration = pgc["duration"].int ?? parseDuration(text: pgc["duration_text"].string)
                        let cid = pgc["cid"].int
                        let plays = pgc["stat"]["play"].int ?? 0
                        return VideoItem(id: bvid, title: title, coverImageURL: coverURL, authorName: authorName, viewCount: plays, duration: duration, cid: cid)
                    }
                    return nil
                }

                if videos.isEmpty {
                    errorMessage = "关注流为空或解析失败"
                }

                videoItems.append(contentsOf: videos)
                page += 1
                hasMore = json["data"]["has_more"].boolValue && !videos.isEmpty
            } catch {
                errorMessage = "获取关注动态失败：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func parseDuration(text: String?) -> Int {
        guard let text else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return parts.reversed().enumerated().reduce(0) { acc, pair in
            let (idx, val) = pair
            return acc + val * Int(pow(60.0, Double(idx)))
        }
    }
}
