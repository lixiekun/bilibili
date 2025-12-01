import Foundation
import Alamofire
import SwiftProtobuf
import Gzip
import SwiftyXMLParser

class DanmakuService {
    
    enum DanmakuError: Error {
        case networkError(Error)
        case invalidData
        case decompressionFailed
        case parsingFailed
    }
    
    // 优先使用 Protobuf
    // 如果传入了 duration (秒)，则会尝试加载所有分段
    func fetchDanmaku(cid: Int, duration: Int = 0) async throws -> [Danmaku] {
        do {
            // 1. 尝试 Protobuf
            return try await fetchDanmakuProtobuf(cid: cid, duration: duration)
        } catch {
            print("Protobuf fetch failed: \(error), falling back to XML")
            // 2. 回退到 XML
            return try await fetchDanmakuXML(cid: cid)
        }
    }
    
    // MARK: - Protobuf Implementation
    
    private func fetchDanmakuProtobuf(cid: Int, duration: Int) async throws -> [Danmaku] {
        // B站 Web 端现用接口: https://api.bilibili.com/x/v2/dm/web/seg.so
        let url = "https://api.bilibili.com/x/v2/dm/web/seg.so"
        
        // 计算分段数，每段 6 分钟 (360秒)
        let segmentDuration = 360
        let totalSegments = duration > 0 ? Int(ceil(Double(duration) / Double(segmentDuration))) : 1
        
        // 并发加载所有分段
        return try await withThrowingTaskGroup(of: [Danmaku].self) { group in
            for i in 1...max(1, totalSegments) {
                group.addTask {
                    let parameters: Parameters = [
                        "type": 1,
                        "oid": cid,
                        "segment_index": i
                    ]
                    
                    let headers: HTTPHeaders = [
                        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
                    ]
                    
                    let data = try await NetworkClient.shared
                        .request(url, parameters: parameters, headers: headers)
                        .serializingData()
                        .value
                    
                    let reply = try DmSegMobileReply(serializedData: data)
                    
                    return reply.elems.compactMap { elem in
                        let color = String(format: "#%06X", elem.color)
                        let mode: Int
                        switch elem.mode {
                        case 4: mode = 4
                        case 5: mode = 5
                        default: mode = 1
                        }
                        let time = Double(elem.progress) / 1000.0
                        
                        return Danmaku(
                            id: String(elem.id),
                            time: time,
                            mode: mode,
                            fontSize: Int(elem.fontsize),
                            color: color,
                            userId: String(elem.midHash),
                            text: elem.content,
                            date: elem.ctime
                        )
                    }
                }
            }
            
            var allDanmakus: [Danmaku] = []
            for try await segmentDanmakus in group {
                allDanmakus.append(contentsOf: segmentDanmakus)
            }
            
            return allDanmakus.sorted { $0.time < $1.time }
        }
    }
    
    // MARK: - XML Implementation (Modernized)
    
    private func fetchDanmakuXML(cid: Int) async throws -> [Danmaku] {
        let urlString = "https://api.bilibili.com/x/v1/dm/list.so?oid=\(cid)"
        
        let headers: HTTPHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]
        
        let data = try await NetworkClient.shared
            .request(urlString, headers: headers)
            .serializingData()
            .value
        
        // 使用 GzipSwift 解压
        let xmlData: Data
        if data.isGzipped {
            xmlData = try data.gunzipped()
        } else {
            xmlData = data
        }
        
        return parseXML(data: xmlData)
    }
    
    private func parseXML(data: Data) -> [Danmaku] {
        let xml = XML.parse(data)
        
        // SwiftyXMLParser 路径: <i> <d>...</d> </i>
        var list: [Danmaku] = []
        
        for element in xml["i", "d"] {
            if let p = element.attributes["p"], let content = element.text {
                if let danmaku = Danmaku(attributes: p, content: content) {
                    list.append(danmaku)
                }
            }
        }
        
        return list.sorted { $0.time < $1.time }
    }
}
