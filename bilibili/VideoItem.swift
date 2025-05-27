import Foundation

struct VideoItem: Identifiable, Decodable {
    let id: String // 假设 API 返回的视频有唯一 ID
    let title: String
    let coverImageURL: String // 封面图片的 URL
    let authorName: String
    // 你可以根据实际 API 返回的数据添加更多字段，例如播放量、时长等

    // 为了方便演示，我们使用假数据。你需要根据实际 API 的字段名来调整 CodingKeys
    // 如果 API 返回的字段名与你的结构体属性名完全一致，则不需要 CodingKeys
    enum CodingKeys: String, CodingKey {
        case id = "bvid" // 假设 API 返回的视频 ID 字段是 "bvid"
        case title
        case coverImageURL = "pic" // 假设 API 返回的封面图字段是 "pic"
        case authorName = "owner_name" // 假设 API 返回的作者名字段是 "owner_name"
    }
}

// 这是一个示例用的 API 响应结构，你需要根据实际的 API 文档来调整
struct RecommendationResponse: Decodable {
    let data: RecommendationData // 假设 API 外层有一个 "data" 字段
}

struct RecommendationData: Decodable {
    let items: [VideoItem] // 假设 "data" 里面有一个 "items" 数组包含视频列表
} 