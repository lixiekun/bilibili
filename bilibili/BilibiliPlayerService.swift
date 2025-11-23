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

        // 多档清晰度尝试，优先高，再降级，强制选 AVC 流
        let qnList = [120, 112, 80]
        for qn in qnList {
            // 先尝试 dash（fnval 16，含 AVC HLS），不行再 durl/mp4
            if let info = try await requestPlayURL(bvid: bvid, cid: resolvedCID, qn: qn, fnval: 16) {
                return info
            }
            if let info = try await requestPlayURL(bvid: bvid, cid: resolvedCID, qn: qn, fnval: 0) {
                return info
            }
        }
        throw PlayerError.noPlayableURL
    }

    private func requestPlayURL(bvid: String, cid: Int, qn: Int, fnval: Int) async throws -> PlayInfo? {
        var components = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        var signer = BilibiliWBI()
        let signedParams = try await signer.sign(params: [
            "bvid": bvid,
            "cid": "\(cid)",
            "fnval": "\(fnval)", // 0: durl/mp4, 16: dash/HLS
            "fourk": "1",
            "qn": "\(qn)",
            "fnver": "0",
            "platform": "pc",
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
                print("playurl selected durl qn=\(qn) fnval=\(fnval) primary=\(primary?.prefix(80) ?? "") backup=\(backup?.prefix(80) ?? "") chosen=\(chosen.prefix(120))")
                #endif
                return PlayInfo(url: url)
            }
        }

        // 如无 durl 再尝试 dash AVC
        if let dash = json["data"]["dash"].dictionary {
            let hasHDR = dash["hdr"] != nil || dash["dolby"] != nil
            if hasHDR {
                #if DEBUG
                print("skip dash because of HDR/Dolby")
                #endif
                return nil
            }
            let videos = dash["video"]?.arrayValue ?? []
            let sorted = videos.sorted { $0["id"].intValue > $1["id"].intValue }
            
            // 1. 尝试 HEVC (codecid 12) - 适合真机，模拟器可能绿屏
            #if !targetEnvironment(simulator)
            if let hevc = sorted.first(where: { $0["codecid"].intValue == 12 }),
               let baseURL = hevc["baseUrl"].string ?? hevc["base_url"].string,
               let url = URL(string: baseURL) {
                #if DEBUG
                print("playurl selected dash HEVC id=\(hevc["id"].intValue) url=\(baseURL.prefix(120))")
                #endif
                return PlayInfo(url: url)
            }
            #endif
            
            // 2. 尝试 AVC (codecid 7) - 兼容性最好
            if let avc = sorted.first(where: { $0["codecid"].intValue == 7 }),
               let baseURL = avc["baseUrl"].string ?? avc["base_url"].string,
               let url = URL(string: baseURL) {
                #if DEBUG
                print("playurl selected dash AVC id=\(avc["id"].intValue) url=\(baseURL.prefix(120))")
                #endif
                return PlayInfo(url: url)
            }
            
            // 3. 兜底 (任意格式)
            if let first = sorted.first,
               let baseURL = first["baseUrl"].string ?? first["base_url"].string,
               let url = URL(string: baseURL) {
                #if DEBUG
                print("playurl selected dash fallback id=\(first["id"].intValue) codecid=\(first["codecid"].intValue) url=\(baseURL.prefix(120))")
                #endif
                return PlayInfo(url: url)
            }
        }

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
