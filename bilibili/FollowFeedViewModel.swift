import SwiftUI
import SwiftyJSON
import Alamofire

@MainActor
final class FollowFeedViewModel: ObservableObject {
    @Published var videoItems: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    private var seenIDs = Set<String>()

    // 使用 polymer 动态接口，需登录 Cookie 才有关注流
    private let feedBaseURL = URL(string: "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all")!
    private var offset: String? = nil // offset 由后端返回，用于继续向后翻页；为空表示第一页
    private var hasMore: Bool = true

    func refresh() {
        guard !isLoading else { return }
        offset = nil // 重置 offset，从第一页开始
        hasMore = true
        videoItems.removeAll()
        errorMessage = nil
        seenIDs.removeAll()
        fetch()
    }

    func fetch() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                var components = URLComponents(url: feedBaseURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "type", value: "video"),
                    URLQueryItem(name: "platform", value: "web"),
                    URLQueryItem(name: "timezone_offset", value: "28800")
                ]
                // offset 由后端返回，用于继续向后翻页；为空表示第一页
                if let offset = offset {
                    components.queryItems?.append(URLQueryItem(name: "offset", value: offset))
                }
                guard let url = components.url else { return }

                let headers: HTTPHeaders = [
                    "Referer": "https://www.bilibili.com",
                    "User-Agent": "Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)"
                ]

                let allCookies = HTTPCookieStorage.shared.cookies ?? []

                let data = try await NetworkClient.shared
                    .request(url, method: .get, headers: headers)
                    .serializingData()
                    .value

                let json = try JSON(data: data)
                #if DEBUG
                let rawPreview = String(data: data, encoding: .utf8) ?? ""
                let cookieString = allCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        // print("Follow feed cookies: \(cookieString)")
        // print("Follow feed code=\(json["code"].intValue) message=\(json["message"].stringValue) items=\(json["data"]["items"].arrayValue.count)")
        // print("Follow feed raw preview: \(rawPreview.prefix(2000))")
        #endif

                if json["code"].intValue != 0 {
                    throw NSError(domain: "FollowFeed", code: json["code"].intValue, userInfo: [NSLocalizedDescriptionKey: json["message"].stringValue])
                }

                let items = json["data"]["items"].arrayValue
                let videos: [VideoItem] = items.compactMap { item in
                    let modules = item["modules"]
                    let authorName = modules["module_author"]["name"].string ?? "未知UP"
                    let major = modules["module_dynamic"]["major"]
                    // 动态统计信息通常在 modules.module_stat 下
                    let moduleStat = modules["module_stat"]

                    if major["archive"].dictionary != nil {
                        let archive = major["archive"]
                        let bvid = archive["bvid"].stringValue
                        let title = archive["title"].stringValue
                        guard let coverURL = URL(string: archive["cover"].stringValue) else { return nil }
                        // 时长：从 duration_text 获取（字符串格式，如 "14:31"）
                        let duration = archive["duration"].int ?? 
                                     parseDuration(text: archive["duration_text"].string ?? archive["durationText"].string)
                        let cid = archive["cid"].int
                        
                        // 播放量：从 archive.stat.play 获取（字符串格式，如 "1.6万"）
                        // 根据实际 API，play 字段是字符串格式，需要解析
                        let playString = archive["stat"]["play"].string ?? ""
                        let plays = parseViewCount(playString)
                        
                        return VideoItem(id: bvid, title: title, coverImageURL: coverURL, authorName: authorName, viewCount: plays, duration: duration, cid: cid)
                    } else if major["pgc"].dictionary != nil {
                        let pgc = major["pgc"]
                        let bvid = pgc["bvid"].string ?? UUID().uuidString
                        let title = pgc["title"].string ?? pgc["ep_title"].string ?? "PGC"
                        guard let coverURL = URL(string: pgc["cover"].stringValue) else { return nil }
                        // 时长：从 duration_text 获取（字符串格式）
                        let duration = pgc["duration"].int ?? 
                                     parseDuration(text: pgc["duration_text"].string ?? pgc["durationText"].string)
                        let cid = pgc["cid"].int
                        // 播放量：从 pgc.stat.play 获取（字符串格式）
                        let playString = pgc["stat"]["play"].string ?? ""
                        let plays = parseViewCount(playString)
                        return VideoItem(id: bvid, title: title, coverImageURL: coverURL, authorName: authorName, viewCount: plays, duration: duration, cid: cid)
                    }
                    return nil
                }

                let unique = videos.filter { seenIDs.insert($0.id).inserted }
                let nextHasMore = json["data"]["has_more"].boolValue
                // 若本页去重后为空且后端还有分页，使用 offset 继续翻页，避免卡在"加载中"
                let nextOffset = json["data"]["offset"].string
                
                if unique.isEmpty {
                    if nextHasMore, nextOffset != nil, nextOffset != offset {
                        offset = nextOffset
                        isLoading = false
                        fetch()
                        return
                    } else {
                        // 没有更多数据或 offset 没有变化，停止加载
                        hasMore = false
                        isLoading = false
                        return
                    }
                }

                videoItems.append(contentsOf: unique)
                hasMore = nextHasMore
                offset = nextOffset
            } catch {
                errorMessage = "获取关注动态失败：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func parseDuration(text: String?) -> Int {
        guard let text else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return parts.reversed().enumerated().reduce(0) { acc, pair in
            let (idx, val) = pair
            return acc + val * Int(pow(60.0, Double(idx)))
        }
    }
    
    /// 解析播放量字符串，支持 "1.6万"、"1234"、"1000万" 等格式
    private func parseViewCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        
        // 如果直接是数字字符串，直接转换
        if let intValue = Int(text) {
            return intValue
        }
        
        // 处理带单位的字符串
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // 处理 "万" 单位
        if trimmed.hasSuffix("万") {
            let numberPart = String(trimmed.dropLast())
            if let value = Double(numberPart) {
                return Int(value * 10000)
            }
        }
        
        // 处理 "亿" 单位
        if trimmed.hasSuffix("亿") {
            let numberPart = String(trimmed.dropLast())
            if let value = Double(numberPart) {
                return Int(value * 100000000)
            }
        }
        
        // 处理 "千" 单位
        if trimmed.hasSuffix("千") {
            let numberPart = String(trimmed.dropLast())
            if let value = Double(numberPart) {
                return Int(value * 1000)
            }
        }
        
        // 如果无法解析，返回 0
        return 0
    }
}
