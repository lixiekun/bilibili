import SwiftUI

@MainActor // 确保对 UI 的更新在主线程进行
class RecommendationViewModel: ObservableObject {
    @Published var videoItems: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

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
                let decodedResponse = try JSONDecoder().decode(RecommendationResponse.self, from: data)
                self.videoItems = decodedResponse.data.list

            } catch {
                self.errorMessage = "获取推荐失败: \(error.localizedDescription)"
                print("错误: \(error)")
            }
            self.isLoading = false
        }
    }
}

private struct RecommendationResponse: Decodable {
    let data: DataContainer

    struct DataContainer: Decodable {
        let list: [VideoItem]
    }
}
