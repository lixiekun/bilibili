import Foundation
import SwiftyJSON

/// 精简后的视频数据模型，对应 Bilibili popular/动态等接口的核心字段。
struct VideoItem: Identifiable, Hashable {
    let id: String // bvid
    let title: String
    let coverImageURL: URL
    let authorName: String
    let viewCount: Int
    let duration: Int // 单位：秒
    let cid: Int?

    init?(
        id: String,
        title: String,
        coverImageURL: URL?,
        authorName: String,
        viewCount: Int,
        duration: Int,
        cid: Int?
    ) {
        guard let coverImageURL else { return nil }
        self.id = id
        self.title = title
        self.coverImageURL = coverImageURL
        self.authorName = authorName
        self.viewCount = viewCount
        self.duration = duration
        self.cid = cid
    }

    init?(json: JSON) {
        let id = json["bvid"].string ?? json["id"].string ?? ""
        let title = json["title"].string ?? ""
        let coverString = json["pic"].string ?? json["cover"].string
        let authorName = json["owner"]["name"].string ?? json["module_author"]["name"].string ?? "未知UP"
        let viewCount = json["stat"]["view"].int ?? json["stat"]["play"].int ?? json["play"].int ?? 0
        let duration = json["duration"].int ?? VideoItem.parseDuration(text: json["durationText"].string ?? json["duration_text"].string)
        let cid = json["cid"].int

        guard !id.isEmpty, !title.isEmpty, let coverURL = URL(string: coverString ?? "") else { return nil }
        self.init(id: id, title: title, coverImageURL: coverURL, authorName: authorName, viewCount: viewCount, duration: duration, cid: cid)
    }

    private static func parseDuration(text: String?) -> Int {
        guard let text else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return parts.reversed().enumerated().reduce(0) { acc, pair in
            let (idx, val) = pair
            return acc + val * Int(pow(60.0, Double(idx)))
        }
    }
}

// MARK: - Preview helpers
extension VideoItem {
    static func mock(id: String, title: String, author: String, views: Int, duration: Int) -> VideoItem {
        return VideoItem(
            id: id,
            title: title,
            coverImageURL: URL(string: "https://i0.hdslb.com/bfs/archive/placeholder.jpg")!,
            authorName: author,
            viewCount: views,
            duration: duration,
            cid: 0
        )!
    }
}
