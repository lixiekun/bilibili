import SwiftUI
import SwiftyJSON
import Alamofire

@MainActor // 确保对 UI 的更新在主线程进行
class RecommendationViewModel: ObservableObject {
    @Published var videoItems: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let baseURL = URL(string: "https://api.bilibili.com/x/web-interface/popular")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()
    private var hasMore: Bool = true
    private var seenIDs: Set<String> = []

    var canLoadMore: Bool { hasMore && !isLoading }

    func fetchRecommendations() {
        guard canLoadMore else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let rand = Int.random(in: 0...Int.max)
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
                let randomPage = Int.random(in: 1...20) // 每次请求随机页提升随机性
                components.queryItems = [
                    URLQueryItem(name: "ps", value: "20"),
                    URLQueryItem(name: "pn", value: "\(randomPage)"),
                    URLQueryItem(name: "_ts", value: "\(Int(Date().timeIntervalSince1970))"),
                    URLQueryItem(name: "rand", value: "\(rand)")
                ]
                guard let url = components.url else { return }

                let headers: HTTPHeaders = [
                    "Referer": "https://www.bilibili.com",
                    "User-Agent": "Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)"
                ]

                let data = try await NetworkClient.shared
                    .request(url, method: .get, headers: headers)
                    .serializingData()
                    .value

                let json = try JSON(data: data)
                let list = json["data"]["list"].arrayValue
                let mapped: [VideoItem] = list.compactMap { VideoItem(json: $0) }
                let uniqueNew = mapped.filter { seenIDs.insert($0.id).inserted }

                #if DEBUG

                #endif

                if uniqueNew.isEmpty {
                    hasMore = false
                } else {
                    self.videoItems.append(contentsOf: uniqueNew)
                    hasMore = true
                }

            } catch {
                self.errorMessage = "获取推荐失败: \(error.localizedDescription)"
                print("错误: \(error)")
            }
            self.isLoading = false
        }
    }

    func refresh() {
        guard !isLoading else { return }
        hasMore = true
        seenIDs.removeAll()
        videoItems = []
        fetchRecommendations()
    }
}
