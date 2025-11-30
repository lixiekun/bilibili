import SwiftUI
import SwiftyJSON
import Alamofire

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var items: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let url = URL(string: "https://api.bilibili.com/x/v2/history")!
    
    func fetch() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let headers: HTTPHeaders = [
                    "Referer": "https://www.bilibili.com",
                    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
                ]
                
                // 必须带 Cookie 才能获取历史记录
                let cookies = HTTPCookieStorage.shared.cookies ?? []
                if cookies.isEmpty {
                    throw NSError(domain: "History", code: -1, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
                }
                
                let data = try await NetworkClient.shared
                    .request(url, method: .get, headers: headers)
                    .serializingData()
                    .value
                
                let json = try JSON(data: data)
                if json["code"].intValue != 0 {
                    throw NSError(domain: "History", code: json["code"].intValue, userInfo: [NSLocalizedDescriptionKey: json["message"].stringValue])
                }
                
                let list = json["data"].arrayValue
                // 历史记录接口的数据结构稍有不同，需要适配
                // 核心字段在 "aid", "bvid", "title", "pic", "owner.name", "duration"
                self.items = list.compactMap { item -> VideoItem? in
                    let id = item["bvid"].stringValue
                    let title = item["title"].stringValue
                    let cover = item["pic"].stringValue
                    let author = item["owner"]["name"].stringValue
                    // viewAt = item["view_at"].int // 观看时间
                    // progress = item["progress"].int // 观看进度
                    
                    // 历史记录里可能没有完整的 stat 统计，用 progress 暂时顶替 viewCount 展示？或者 0
                    // 还是保留原始 VideoItem 结构，ViewCount 填 0 吧
                    
                    // 时长
                    let duration = item["duration"].int ?? 0
                    
                    guard !id.isEmpty, let coverURL = URL(string: cover) else { return nil }
                    
                    return VideoItem(
                        id: id,
                        title: title,
                        coverImageURL: coverURL,
                        authorName: author,
                        viewCount: 0, // 历史接口不返回总播放量
                        duration: duration,
                        cid: item["cid"].int
                    )
                }
                
            } catch {
                self.errorMessage = "获取历史记录失败：\(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }
}

