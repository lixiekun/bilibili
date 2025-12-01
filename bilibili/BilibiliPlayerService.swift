import Foundation
import SwiftyJSON
import AVKit
import Alamofire

struct BilibiliPlayerService {
    struct DashStreamInfo {
        let url: URL
        let backupUrl: URL?
        let bandwidth: Int
        let codecs: String
        let width: Int
        let height: Int
        let frameRate: String
        let initializationRange: String
        let indexRange: String
    }

    enum PlaySource {
        case url(URL)
        case dash(video: DashStreamInfo, audio: DashStreamInfo)
    }

    struct PlayInfo: Identifiable {
        let id = UUID()
        let source: PlaySource
        let quality: Int
        let format: String
        
        // 兼容旧代码的便利属性，只在单 URL 模式下有效
        var url: URL? {
            if case .url(let u) = source { return u }
            return nil
        }
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

        // 多档清晰度尝试
        // 1. 尝试 DASH (fnval=16) - 优先获取 4K/1080P60
        // 现在我们有了 ResourceLoader，可以自信地请求 DASH 了
        let qnList = [120, 116, 112, 80, 64]
        
        for qn in qnList {
            if let info = try await requestPlayURL(bvid: bvid, cid: resolvedCID, qn: qn, fnval: 16, platform: "pc") {
                return info
            }
        }
        
        // 2. 兜底尝试 HLS (fnval=4048)
        if let info = try await requestPlayURL(bvid: bvid, cid: resolvedCID, qn: 80, fnval: 4048, platform: "ios") {
            return info
        }
        
        throw PlayerError.noPlayableURL
    }

    private func filterAndSortURLs(baseUrl: String?, backupUrls: [JSON]?) -> URL? {
        var urls = [String]()
        if let b = baseUrl, !b.isEmpty { urls.append(b) }
        if let backups = backupUrls {
            urls.append(contentsOf: backups.compactMap { $0.stringValue })
        }
        
        // 过滤掉 known problematic PCDN domains
        let pcdnDomains = ["szbdyd.com", "mcdn.bilivideo.cn"]
        
        let sorted = urls.sorted { lhs, rhs in
            let lhsIsPCDN = pcdnDomains.contains(where: { lhs.contains($0) })
            let rhsIsPCDN = pcdnDomains.contains(where: { rhs.contains($0) })
            
            if lhsIsPCDN && !rhsIsPCDN { return false } // PCDN 排后面
            if !lhsIsPCDN && rhsIsPCDN { return true }
            return lhs < rhs // 默认字典序
        }
        
        if let first = sorted.first {
            return URL(string: first)
        }
        return nil
    }
    
    private func requestPlayURL(bvid: String, cid: Int, qn: Int, fnval: Int, platform: String = "pc") async throws -> PlayInfo? {
        var components = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        var signer = BilibiliWBI()
        let signedParams = try await signer.sign(params: [
            "bvid": bvid,
            "cid": "\(cid)",
            "fnval": "\(fnval)", // 0: durl/mp4, 16: dash, 4048: hls
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
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
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
            return nil 
        }
        
        let quality = json["data"]["quality"].intValue
        let format = json["data"]["format"].stringValue
        
        // 1. 解析 DASH
        if let dash = json["data"]["dash"].dictionary {
            
            // 筛选最佳视频流 (参考 Demo 逻辑，避开不支持的 Codec)
            let videoCodecBlackList = ["avc1.640034"]
            let videos = dash["video"]?.arrayValue ?? []
            let audios = dash["audio"]?.arrayValue ?? []
            
            var selectedVideo: JSON?
            
            // 优先找非黑名单的流
            for v in videos {
                let codec = v["codecs"].stringValue
                if !videoCodecBlackList.contains(codec) {
                    selectedVideo = v
                    break
                }
            }
            // 如果都命中黑名单（罕见），则降级使用第一个
            if selectedVideo == nil {
                selectedVideo = videos.first
            }
            
            let selectedAudio = audios.first // 音频通常没问题
            
            if let video = selectedVideo, let audio = selectedAudio {
                
                // 使用 URL 筛选逻辑
                let vUrl = filterAndSortURLs(baseUrl: video["baseUrl"].string, backupUrls: video["backupUrl"].array)
                let aUrl = filterAndSortURLs(baseUrl: audio["baseUrl"].string, backupUrls: audio["backupUrl"].array)
                
                if let vUrl = vUrl, let aUrl = aUrl {
                    
                    let vInfo = DashStreamInfo(
                        url: vUrl,
                        backupUrl: nil,
                        bandwidth: video["bandwidth"].intValue,
                        codecs: video["codecs"].stringValue,
                        width: video["width"].intValue,
                        height: video["height"].intValue,
                        frameRate: video["frameRate"].stringValue,
                        initializationRange: video["SegmentBase"]["Initialization"].stringValue,
                        indexRange: video["SegmentBase"]["indexRange"].stringValue
                    )
                    
                    let aInfo = DashStreamInfo(
                        url: aUrl,
                        backupUrl: nil,
                        bandwidth: audio["bandwidth"].intValue,
                        codecs: audio["codecs"].stringValue,
                        width: 0,
                        height: 0,
                        frameRate: "",
                        initializationRange: audio["SegmentBase"]["Initialization"].stringValue,
                        indexRange: audio["SegmentBase"]["indexRange"].stringValue
                    )
                    
                    #if DEBUG
                    print("playurl matched DASH quality=\(quality) codec=\(vInfo.codecs)")
                    #endif
                    return PlayInfo(source: .dash(video: vInfo, audio: aInfo), quality: quality, format: "dash")
                }
            }
        }

        // 2. 解析 Durl (MP4/FLV/HLS)
        // B站返回的 HLS 流通常也在 durl 中，或者作为特殊的 format
        if let durl = json["data"]["durl"].arrayValue.first {
            let primary = durl["url"].string
            let backup = durl["backup_url"].arrayValue.first?.string
            let chosen = backup ?? primary
            if let chosen, let url = URL(string: chosen) {
                #if DEBUG
                print("playurl matched DURL/HLS quality=\(quality) url=\(chosen.prefix(50))")
                #endif
                // 只要拿到 url，就认为是可播放的（MP4 或 HLS）
                return PlayInfo(source: .url(url), quality: quality, format: format)
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
