import Foundation

/// 精简后的视频数据模型，对应 Bilibili popular 接口的核心字段。
struct VideoItem: Identifiable, Decodable, Hashable {
    let id: String // bvid
    let title: String
    let coverImageURL: URL
    let authorName: String
    let viewCount: Int
    let duration: Int // 单位：秒

    enum CodingKeys: String, CodingKey {
        case id = "bvid"
        case title
        case coverImageURL = "pic"
        case owner
        case stat
        case duration
    }

    enum OwnerKeys: String, CodingKey {
        case name
    }

    enum StatKeys: String, CodingKey {
        case view
    }

    init(
        id: String,
        title: String,
        coverImageURL: URL,
        authorName: String,
        viewCount: Int,
        duration: Int
    ) {
        self.id = id
        self.title = title
        self.coverImageURL = coverImageURL
        self.authorName = authorName
        self.viewCount = viewCount
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let coverURL = try container.decodeIfPresent(URL.self, forKey: .coverImageURL)
        coverImageURL = coverURL ?? URL(string: "https://i0.hdslb.com/bfs/archive/placeholder.jpg")!

        let ownerContainer = try container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner)
        authorName = try ownerContainer.decode(String.self, forKey: .name)

        let statContainer = try container.nestedContainer(keyedBy: StatKeys.self, forKey: .stat)
        viewCount = try statContainer.decodeIfPresent(Int.self, forKey: .view) ?? 0

        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0
    }
}

// MARK: - Preview helpers
extension VideoItem {
    static func mock(id: String, title: String, author: String, views: Int, duration: Int) -> VideoItem {
        VideoItem(
            id: id,
            title: title,
            coverImageURL: URL(string: "https://i0.hdslb.com/bfs/archive/placeholder.jpg")!,
            authorName: author,
            viewCount: views,
            duration: duration
        )
    }
}
