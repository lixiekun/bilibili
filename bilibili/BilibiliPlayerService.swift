import Foundation
import SwiftyJSON
import AVKit
import Alamofire

struct BilibiliPlayerService {
    struct PlayInfo {
        let url: URL
    }

    enum PlayerError: Error {
        case missingCID
        case noPlayableURL
        case badResponse
        case apiError(code: Int, message: String)
        case invalidURL
    }

    func fetchPlayURL(bvid: String, cid: Int?) async throws -> PlayInfo {
        let resolvedCID: Int
        if let cid {
            resolvedCID = cid
        } else {
            resolvedCID = try await fetchCID(bvid: bvid)
        }

        // 多档清晰度尝试，优先高，再降级
        // AVPlayer 原生不支持 B 站的 Dash (音视频分离)，除非是 HLS
        // 这里我们专注于请求 MP4 (durl)，虽然画质上限通常是 1080P，但兼容性最好
        let qnList = [120, 116, 112, 80] // 120:4K, 116:1080P60, 112:1080P+, 80:1080P
        for qn in qnList {
            // 1. 尝试 HLS (fnval=4048) - AVPlayer 原生支持 m3u8
            // 这通常能获得比普通 MP4 更好的画质（1080P+），但可能需要特定的 platform
            if let info = try await requestPlayURL(bvid: bvid, cid: resolvedCID, qn: qn, fnval: 4048, platform: "html5") {
                return info
            }
            
            // 2. 尝试 MP4 (fnval=1)
            if let info = try await requestPlayURL(bvid: bvid, cid: resolvedCID, qn: qn, fnval: 1, platform: "html5") {
                return info
            }
        }
        // 兜底尝试默认
        if let info = try await requestPlayURL(bvid: bvid, cid: resolvedCID, qn: 80, fnval: 0, platform: "html5") {
            return info
        }
        
        throw PlayerError.noPlayableURL
    }

    private func requestPlayURL(bvid: String, cid: Int, qn: Int, fnval: Int, platform: String = "pc") async throws -> PlayInfo? {
        var components = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        var signer = BilibiliWBI()
        let signedParams = try await signer.sign(params: [
            "bvid": bvid,
            "cid": "\(cid)",
            "fnval": "\(fnval)", // 0: durl/mp4, 16: dash/HLS
            "fourk": "1",
            "qn": "\(qn)",
            "fnver": "0",
            "platform": platform,
            "otype": "json"
        ])
        components.queryItems = signedParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw PlayerError.badResponse }

        let headers: HTTPHeaders = [
            "Referer": "https://www.bilibili.com",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]

        let data = try await NetworkClient.shared
            .request(url, method: .get, headers: headers)
            .serializingData()
            .value

        let json = try JSON(data: data)
        #if DEBUG
        print("playurl qn=\(qn) fnval=\(fnval) request url=\(url.absoluteString)")
        print("playurl response code=\(json["code"].intValue) message=\(json["message"].stringValue) quality=\(json["data"]["quality"].intValue) format=\(json["data"]["format"].stringValue) codecid=\(json["data"]["video_codecid"].intValue)")
        print("playurl raw preview: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
        #endif
        if json["code"].intValue != 0 {
            throw PlayerError.apiError(code: json["code"].intValue, message: json["message"].stringValue)
        }

        // 优先 durl/mp4，若有 backup_url 优先使用
        if let durl = json["data"]["durl"].arrayValue.first {
            let primary = durl["url"].string
            let backup = durl["backup_url"].arrayValue.first?.string
            let chosen = backup ?? primary
            if let chosen, let url = URL(string: chosen) {
                #if DEBUG
                print("playurl selected durl qn=\(qn) fnval=\(fnval) quality=\(json["data"]["quality"].intValue) url=\(chosen.prefix(100))")
                #endif
                return PlayInfo(url: url)
            }
        }

        // AVPlayer 无法直接播放 B 站的 Dash (m4s) 音视频分离流，因此忽略 Dash 数据
        // 如果未来需要支持 4K/Dash，需要引入 ffmpeg 或自行实现 Dash 播放器
        
        return nil
    }

    private func fetchCID(bvid: String) async throws -> Int {
        var components = URLComponents(string: "https://api.bilibili.com/x/player/pagelist")!
        components.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "jsonp", value: "jsonp")
        ]
        guard let url = components.url else { throw PlayerError.badResponse }

        let headers: HTTPHeaders = [
            "Referer": "https://www.bilibili.com",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]

        let data = try await NetworkClient.shared
            .request(url, method: .get, headers: headers)
            .serializingData()
            .value

        let json = try JSON(data: data)
        #if DEBUG
        print("pagelist url=\(url.absoluteString)")
        print("pagelist code=\(json["code"].intValue) message=\(json["message"].stringValue) cid=\(json["data"].arrayValue.first?["cid"].int ?? -1)")
        print("pagelist raw preview: \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
        #endif
        if json["code"].intValue != 0 {
            throw PlayerError.apiError(code: json["code"].intValue, message: json["message"].stringValue)
        }
        guard let firstCID = json["data"].arrayValue.first?["cid"].int else {
            throw PlayerError.missingCID
        }
        return firstCID
    }
}
