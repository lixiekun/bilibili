import Foundation
import Alamofire

class HistoryService {
    static let shared = HistoryService()
    
    private let reportURL = URL(string: "https://api.bilibili.com/x/v2/history/report")!
    
    /// 上报播放进度
    /// - Parameters:
    ///   - bvid: 视频 BVID (如果只有 bvid，需要转 avid，或者直接用 aid 参数)
    ///   - cid: 视频 CID
    ///   - progress: 当前播放进度（秒）
    ///   - duration: 视频总时长（秒）
    func reportProgress(bvid: String, cid: Int, progress: Int, duration: Int) async {
        // 历史记录上报接口通常需要 aid (avid)，而不是 bvid。
        // 但 Web 端心跳接口 (x/click-interface/web/heartbeat) 支持 bvid。
        // 这里我们尝试使用 web 心跳接口，因为它更通用且支持 bvid。
        
        let heartbeatURL = URL(string: "https://api.bilibili.com/x/click-interface/web/heartbeat")!
        
        var components = URLComponents(url: heartbeatURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: "\(cid)"),
            URLQueryItem(name: "played_time", value: "\(progress)"), // 当前播放进度
            URLQueryItem(name: "realtime", value: "\(progress)"), // 实际播放时间？
            URLQueryItem(name: "start_ts", value: "\(Int(Date().timeIntervalSince1970))"),
            URLQueryItem(name: "type", value: "3"), // 3: 视频
            URLQueryItem(name: "dt", value: "2"),
            URLQueryItem(name: "play_type", value: "1")
        ]
        
        // 如果有 duration，也可以带上，虽然接口可能不强制
        
        guard let url = components.url else { return }
        
        let headers: HTTPHeaders = [
            "Referer": "https://www.bilibili.com/video/\(bvid)",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]
        
        // 必须带 Cookie
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        if cookies.isEmpty { return }
        
        do {
            let _ = try await NetworkClient.shared
                .request(url, method: .post, headers: headers)
                .serializingData()
                .value
            // 心跳接口通常返回 code=0 即成功，静默失败即可
        } catch {
            print("History report failed: \(error)")
        }
    }
}

