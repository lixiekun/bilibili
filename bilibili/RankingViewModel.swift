import SwiftUI
import SwiftyJSON
import Alamofire

@MainActor
final class RankingViewModel: ObservableObject, FeedProviding {
    @Published var videoItems: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let url = URL(string: "https://api.bilibili.com/x/web-interface/ranking/v2?rid=0&type=all")!

    func fetch() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let headers: HTTPHeaders = [
                    "Referer": "https://www.bilibili.com",
                    "User-Agent": "Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)"
                ]
                let data = try await NetworkClient.shared
                    .request(url, method: .get, headers: headers)
                    .serializingData()
                    .value
                let json = try JSON(data: data)
                if json["code"].intValue != 0 {
                    throw NSError(domain: "Ranking", code: json["code"].intValue, userInfo: [NSLocalizedDescriptionKey: json["message"].stringValue])
                }
                let list = json["data"]["list"].arrayValue
                videoItems = list.compactMap { VideoItem(json: $0) }
            } catch {
                errorMessage = "获取排行榜失败：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
