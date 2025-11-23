import SwiftUI

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

                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
                request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

                let allCookies = HTTPCookieStorage.shared.cookies ?? []
                let header = HTTPCookie.requestHeaderFields(with: allCookies)
                header.forEach { key, value in
                    request.addValue(value, forHTTPHeaderField: key)
                }

                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let decodedResponse = try JSONDecoder().decode(RecommendationResponse.self, from: data)
                let shuffled = decodedResponse.data.list.shuffled()
                let uniqueNew = shuffled.filter { seenIDs.insert($0.id).inserted }

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

extension RecommendationViewModel {
    /// 用于 SwiftUI 预览的静态数据
    static var preview: RecommendationViewModel {
        let vm = RecommendationViewModel()
        vm.videoItems = [
            .mock(id: "BV1xx411c7mD", title: "史上最强 React Hooks 入门", author: "程序员小明", views: 1254000, duration: 754),
            .mock(id: "BV1jj411k7Tp", title: "苹果 Vision Pro 初体验：空间计算的第一天", author: "数码评测社", views: 842331, duration: 612),
            .mock(id: "BV1zz4y1A7QD", title: "如何在 30 天内自学 SwiftUI", author: "学习笔记本", views: 39214, duration: 445)
        ]
        return vm
    }
}

private struct RecommendationResponse: Decodable {
    let data: DataContainer

    struct DataContainer: Decodable {
        let list: [VideoItem]
    }
}
