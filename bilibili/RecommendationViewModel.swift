import SwiftUI
import SwiftyJSON
import Alamofire

@MainActor // 确保对 UI 的更新在主线程进行
class RecommendationViewModel: ObservableObject {
    @Published var videoItems: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // 使用 B站 Web 端首页推荐流接口
    // 注意：此接口通常需要登录 Cookie 才能获得个性化推荐，否则可能是默认推荐
    private let baseURL = URL(string: "https://api.bilibili.com/x/web-interface/index/top/feed/rcmd")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()
    private var hasMore: Bool = true
    private var seenIDs: Set<String> = []
    private var refreshIdx: Int = 1 // 刷新计数/游标

    var canLoadMore: Bool { hasMore && !isLoading }

    func fetchRecommendations() {
        guard canLoadMore else { return }
        isLoading = true
        errorMessage = nil

        Task {
            // 确保无论发生什么，最后都会把 isLoading 置为 false
            defer { isLoading = false }
            
            do {
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
                // Web 端推荐流参数调整：
                // y_num: 也就是第几刷
                components.queryItems = [
                    URLQueryItem(name: "ps", value: "14"), // 每次获取 14 条
                    URLQueryItem(name: "fresh_idx", value: "\(refreshIdx)"),
                    URLQueryItem(name: "feed_version", value: "V8"),
                    URLQueryItem(name: "fresh_type", value: "4"),
                    URLQueryItem(name: "plat", value: "1"),
                    URLQueryItem(name: "fresh_idx_1h", value: "\(refreshIdx)"),
                    URLQueryItem(name: "brush", value: "\(refreshIdx)")
                ]
                guard let url = components.url else { return }

                let headers: HTTPHeaders = [
                    "Referer": "https://www.bilibili.com",
                    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
                ]

                let data = try await NetworkClient.shared
                    .request(url, method: .get, headers: headers)
                    .serializingData()
                    .value

                let json = try JSON(data: data)
                
                if json["code"].intValue != 0 {
                     print("Recommend API Warning: code=\(json["code"].intValue) msg=\(json["message"].stringValue)")
                }

                let list = json["data"]["item"].arrayValue
                let mapped: [VideoItem] = list.compactMap { VideoItem(json: $0) }
                
                let uniqueNew = mapped.filter { seenIDs.insert($0.id).inserted }

                #if DEBUG
                print("Fetched \(mapped.count) items, unique: \(uniqueNew.count)")
                #endif

                if !uniqueNew.isEmpty {
                    self.videoItems.append(contentsOf: uniqueNew)
                    self.refreshIdx += 1
                }
                
            } catch {
                self.errorMessage = "获取推荐失败: \(error.localizedDescription)"
                print("错误: \(error)")
            }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        hasMore = true
        seenIDs.removeAll()
        refreshIdx = 1
        videoItems = []
        fetchRecommendations()
    }
}
