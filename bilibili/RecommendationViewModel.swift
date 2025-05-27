import SwiftUI

@MainActor // 确保对 UI 的更新在主线程进行
class RecommendationViewModel: ObservableObject {
    @Published var videoItems: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // TODO: 替换为真实的 Bilibili 推荐 API URL
    private let recommendationAPIURL = URL(string: "https://api.bilibili.com/x/web-interface/popular?ps=20&pn=1")! 

    func fetchRecommendations() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: recommendationAPIURL)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                
                // 打印原始 JSON 数据以供调试
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("原始 JSON 响应: \(jsonString)")
                }

                // 注意：这里的 RecommendationResponse.self 和 VideoItem.self 对应你之前定义的结构体
                // 如果 API 直接返回一个视频数组，你需要调整解码逻辑
                // 例如，如果直接返回 [VideoItem]，则解码为 [VideoItem].self
                // 你需要根据实际API返回的JSON结构来调整这里的解码方式
                // 我假设 API 返回的结构是 {"code": 0, "message": "0", "ttl": 1, "data": {"list": [...]}}
                // 所以我们需要一个更外层的结构来匹配这个，或者直接取 "data.list"
                
                // 临时的解码结构，你需要根据实际的API调整
                struct TempAPIResponse: Decodable {
                    struct DataContainer: Decodable {
                        let list: [VideoItem]
                    }
                    let data: DataContainer
                }

                let decodedResponse = try JSONDecoder().decode(TempAPIResponse.self, from: data)
                self.videoItems = decodedResponse.data.list

            } catch {
                self.errorMessage = "获取推荐失败: \(error.localizedDescription)"
                print("错误: \(error)")
            }
            self.isLoading = false
        }
    }
} 