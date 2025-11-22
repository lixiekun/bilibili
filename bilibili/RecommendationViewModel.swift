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
