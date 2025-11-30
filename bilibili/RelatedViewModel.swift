import SwiftUI
import SwiftyJSON
import Alamofire

@MainActor
final class RelatedViewModel: ObservableObject {
    @Published var items: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetch(bvid: String) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let url = URL(string: "https://api.bilibili.com/x/web-interface/view/detail?bvid=\(bvid)")!
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
                    throw NSError(domain: "Related", code: json["code"].intValue, userInfo: [NSLocalizedDescriptionKey: json["message"].stringValue])
                }
                let related = json["data"]["Related"].arrayValue
                items = related.compactMap { VideoItem(json: $0) }
            } catch {
                errorMessage = "相关推荐获取失败：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
