import SwiftUI

@MainActor
final class FollowFeedViewModel: ObservableObject {
    @Published var videoItems: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // 使用 polymer 动态接口，需登录 Cookie 才有关注流
    private let feedBaseURL = URL(string: "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()
    private var page: Int = 1
    private var hasMore: Bool = true

    func refresh() {
        guard !isLoading else { return }
        page = 1
        hasMore = true
        videoItems.removeAll()
        errorMessage = nil
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
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "platform", value: "web"),
                    URLQueryItem(name: "timezone_offset", value: "28800")
                ]
                guard let url = components.url else { return }

                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

                let allCookies = HTTPCookieStorage.shared.cookies ?? []
                let header = HTTPCookie.requestHeaderFields(with: allCookies)
                header.forEach { key, value in
                    request.addValue(value, forHTTPHeaderField: key)
                }

                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }

                let decoded = try JSONDecoder().decode(FollowFeedResponse.self, from: data)
                #if DEBUG
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("Follow feed code=\(decoded.code) message=\(decoded.message) items=\(decoded.data?.items.count ?? 0)")
                print("Follow feed raw preview: \(raw.prefix(2000))")
                #endif
                if decoded.code != 0 {
                    throw NSError(domain: "FollowFeed", code: decoded.code, userInfo: [NSLocalizedDescriptionKey: decoded.message])
                }

                guard let items = decoded.data?.items else {
                    errorMessage = "关注流为空（data 为 nil）"
                    videoItems = []
                    return
                }

                let archives = items.compactMap { $0.toVideoItem }
                if archives.isEmpty {
                    errorMessage = "关注流为空或解析失败"
                }
                videoItems.append(contentsOf: archives)
                page += 1
                hasMore = !archives.isEmpty
            } catch {
                errorMessage = "获取关注动态失败：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

private struct FollowFeedResponse: Decodable {
    let code: Int
    let message: String
    let data: DataContainer?

    struct DataContainer: Decodable {
        let items: [DynamicItem]
    }

    struct DynamicItem: Decodable {
        let modules: Modules

        struct Modules: Decodable {
            let moduleDynamic: ModuleDynamic
            let moduleAuthor: ModuleAuthor

            struct ModuleDynamic: Decodable {
                let major: Major?

                struct Major: Decodable {
                    let type: String?
                    let archive: Archive?
                    let pgc: Pgc?

                    struct Archive: Decodable {
                        let bvid: String
                        let title: String
                        let cover: String
                        let durationText: String?
                        let duration: Int?
                        let stat: Stat?

                        struct Stat: Decodable {
                            let play: Int?
                        }
                    }

                    struct Pgc: Decodable {
                        let bvid: String?
                        let cover: String
                        let title: String?
                        let epTitle: String?
                        let duration: Int?
                        let durationText: String?
                        let stat: Stat?

                        enum CodingKeys: String, CodingKey {
                            case bvid
                            case cover
                            case title
                            case epTitle = "ep_title"
                            case duration
                            case durationText = "duration_text"
                            case stat
                        }

                        struct Stat: Decodable {
                            let play: Int?
                        }
                    }
                }
            }

            struct ModuleAuthor: Decodable {
                let name: String
            }
        }

        var toVideoItem: VideoItem? {
            guard let major = modules.moduleDynamic.major else { return nil }

            if let archive = major.archive, let coverURL = URL(string: archive.cover) {
                let dur = parseDuration(seconds: archive.duration, text: archive.durationText)
                return VideoItem(
                    id: archive.bvid,
                    title: archive.title,
                    coverImageURL: coverURL,
                    authorName: modules.moduleAuthor.name,
                    viewCount: archive.stat?.play ?? 0,
                    duration: dur,
                    cid: nil
                )
            }

            if let pgc = major.pgc,
               let coverURL = URL(string: pgc.cover) {
                let dur = parseDuration(seconds: pgc.duration, text: pgc.durationText)
                let title = pgc.title ?? pgc.epTitle ?? "PGC"
                let vid = pgc.bvid ?? UUID().uuidString
                return VideoItem(
                    id: vid,
                    title: title,
                    coverImageURL: coverURL,
                    authorName: modules.moduleAuthor.name,
                    viewCount: pgc.stat?.play ?? 0,
                    duration: dur,
                    cid: nil
                )
            }

            return nil
        }

        private func parseDuration(seconds: Int?, text: String?) -> Int {
            if let seconds { return seconds }
            guard let text else { return 0 }
            let parts = text.split(separator: ":").compactMap { Int($0) }
            return parts.reversed().enumerated().reduce(0) { acc, pair in
                let (idx, val) = pair
                return acc + val * Int(pow(60.0, Double(idx)))
            }
        }
    }
}
