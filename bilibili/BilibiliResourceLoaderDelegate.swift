import Foundation
import AVFoundation

class BilibiliResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, ObservableObject {
    
    private let videoInfo: BilibiliPlayerService.DashStreamInfo
    private let audioInfo: BilibiliPlayerService.DashStreamInfo
    
    // 使用懒加载或固定 session 以复用连接池
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.name = "com.bilibili.loader.network"
        queue.maxConcurrentOperationCount = 8 
        return URLSession(configuration: config, delegate: nil, delegateQueue: queue)
    }()
    
    // 简单内存缓存，防止重复请求 Sidx（使用 actor 确保并发安全）
    private let sidxCache = SidxCache()
    
    // 增加 debugInfo 属性供外部读取
    @Published var debugInfo: String = ""
    
    // 回调闭包，用于非 Combine 场景或跨线程更新
    var onDebugInfoUpdate: ((String) -> Void)?

    private let videoCodecBlackList = ["avc1.640034"] // high 5.2 is not supported

    // 并发安全的 Sidx 缓存
    private actor SidxCache {
        private var storage: [URL: Data] = [:]

        func get(_ url: URL) -> Data? {
            storage[url]
        }

        func set(_ url: URL, data: Data) {
            storage[url] = data
        }
    }
    
    init(videoInfo: BilibiliPlayerService.DashStreamInfo, audioInfo: BilibiliPlayerService.DashStreamInfo) {
        self.videoInfo = videoInfo
        self.audioInfo = audioInfo
    }
    
    // 辅助方法：使用 session dataTask 下载 Sidx
    private func loadData(url: URL, range: String) async throws -> Data {
        // 1. 查缓存（已在外层处理，这里直接请求）
        // 2. 网络请求
        return try await withCheckedThrowingContinuation { continuation in
            var request = URLRequest(url: url)
            request.setValue("bytes=\(range)", forHTTPHeaderField: "Range")
            request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            
            let task = self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: NSError(domain: "Loader", code: -999, userInfo: [NSLocalizedDescriptionKey: "Invalid Response"]))
                    return
                }
                
                if !(200...299).contains(httpResponse.statusCode) {
                    continuation.resume(throwing: NSError(domain: "Loader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                    return
                }
                
                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "Loader", code: -998, userInfo: [NSLocalizedDescriptionKey: "No Data"]))
                }
            }
            task.resume()
        }
        
        // 注意：这里无法在 continuation 返回后立即写缓存（因为它是 async 且 data 是返回结果）
        // 实际上上面的 loadData 在 returning data 之前无法执行后续代码。
        // 我们需要在 resume 之前写入缓存？
        // 不，resume 之后，await 返回，我们在调用处无法轻易写入（因为 loadData 是 helper）。
        // 所以我们需要在 resume 之前写入。但 withCheckedThrowingContinuation 内部是闭包。
        // 修正：withCheckedThrowingContinuation 返回 data 后，我们在 loadData 方法体里写缓存。
    }
    
    // 重新封装 loadData 以便处理缓存写入
    private func loadSidxData(url: URL, range: String) async throws -> Data {
        // 1. 查缓存
        if let cached = await sidxCache.get(url) {
            return cached
        }

        let data = try await loadData(url: url, range: range)

        // 3. 写缓存
        await sidxCache.set(url, data: data)

        return data
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else { return false }
        
        updateDebugInfo("Req: \(url.lastPathComponent)")
        
        // 1. 处理 Master Playlist 请求
        if url.absoluteString.hasSuffix("master.m3u8") {
            handleMasterPlaylist(loadingRequest)
            return true
        }
        
        // 2. 处理 Video Playlist 请求
        if url.absoluteString.contains("video.m3u8") {
            handleMediaPlaylist(info: videoInfo, loadingRequest: loadingRequest)
            return true
        }
        
        // 3. 处理 Audio Playlist 请求
        if url.absoluteString.contains("audio.m3u8") {
            handleMediaPlaylist(info: audioInfo, loadingRequest: loadingRequest)
            return true
        }

        // 4. 不再拦截 .m4s 请求，让 AVPlayer 直接访问原始 URL (带 Referer)
        
        return false
    }
    
    private func parseRange(_ rangeStr: String) -> (Int64, Int64)? {
        let parts = rangeStr.components(separatedBy: "-")
        guard parts.count == 2,
              let start = Int64(parts[0]),
              let end = Int64(parts[1]) else { return nil }
        return (start, end)
    }
    
    private func handleMasterPlaylist(_ loadingRequest: AVAssetResourceLoadingRequest) {
        let vWidth = videoInfo.width
        let vHeight = videoInfo.height
        var vCodecs = videoInfo.codecs
        
        if videoCodecBlackList.contains(vCodecs) {
             print("Warning: Codec \(vCodecs) is in blacklist")
        }
        
        var supplementCodecs = ""
        if vCodecs == "dvh1.08.07" || vCodecs == "dvh1.08.03" {
            supplementCodecs = vCodecs + "/db4h"
            vCodecs = "hvc1.2.4.L153.b0"
        } else if vCodecs == "dvh1.08.06" {
            supplementCodecs = vCodecs + "/db1p"
            vCodecs = "hvc1.2.4.L150"
        }
        
        if !supplementCodecs.isEmpty {
            supplementCodecs = ",SUPPLEMENTAL-CODECS=\"\(supplementCodecs)\""
        }

        let vBandwidth = videoInfo.bandwidth
        
        let master = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-INDEPENDENT-SEGMENTS
        
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",DEFAULT=YES,AUTOSELECT=YES,URI="custom-scheme://playlist/audio.m3u8"
        
        #EXT-X-STREAM-INF:BANDWIDTH=\(vBandwidth),CODECS="\(vCodecs)"\(supplementCodecs),RESOLUTION=\(vWidth)x\(vHeight),AUDIO="audio"
        custom-scheme://playlist/video.m3u8
        """
        
        if let data = master.data(using: .utf8) {
            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        } else {
            loadingRequest.finishLoading(with: NSError(domain: "Loader", code: -1))
        }
    }
    
    private func handleMediaPlaylist(info: BilibiliPlayerService.DashStreamInfo, loadingRequest: AVAssetResourceLoadingRequest) {
        Task {
            do {
                self.updateDebugInfo("Loading Sidx: \(info.indexRange)")
                
                guard let (indexStart, indexEnd) = parseRange(info.indexRange) else {
                    throw NSError(domain: "Loader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid index range"])
                }
                
                self.updateDebugInfo("Req Sidx: \(indexStart)-\(indexEnd)")
                
                // 使用带缓存的 loadSidxData
                let data = try await loadSidxData(url: info.url, range: "\(indexStart)-\(indexEnd)")
                
                self.updateDebugInfo("Sidx Loaded: \(data.count) bytes")
                
                guard let sidxData = SidxParser.parse(data: data) else {
                    self.updateDebugInfo("Sidx Parse Failed. Data len: \(data.count)")
                    throw NSError(domain: "Loader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse sidx"])
                }
                let segments = sidxData.segments
                let firstOffset = sidxData.firstOffset
                
                self.updateDebugInfo("Segs: \(segments.count) Off: \(firstOffset)")
                
                guard let (initStart, initEnd) = parseRange(info.initializationRange) else {
                    throw NSError(domain: "Loader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid init range"])
                }
                let initLength = initEnd - initStart + 1
                let headerRange = "\(initLength)@\(initStart)"
                
                // 关键：直接使用原始 URL (Demo 方案)
                let originalURLString = info.url.absoluteString
                
                var m3u8 = """
                #EXTM3U
                #EXT-X-VERSION:6
                #EXT-X-TARGETDURATION:\(sidxData.maxSegmentDuration() ?? 5)
                #EXT-X-PLAYLIST-TYPE:VOD
                #EXT-X-MAP:URI="\(originalURLString)",BYTERANGE="\(headerRange)"
                
                """
                
                var currentOffset: Int64 = indexEnd + 1
                
                if firstOffset != 0 {
                     print("Warning: non-zero firstOffset: \(firstOffset)")
                }
                
                for segment in segments {
                    let duration = Double(segment.duration) / Double(sidxData.timescale)
                    m3u8 += "#EXTINF:\(String(format: "%.3f", duration)),\n"
                    m3u8 += "#EXT-X-BYTERANGE:\(segment.size)@\(currentOffset)\n"
                    m3u8 += "\(originalURLString)\n"
                    currentOffset += Int64(segment.size)
                }
                
                m3u8 += "#EXT-X-ENDLIST"
                
                if let responseData = m3u8.data(using: .utf8) {
                    loadingRequest.dataRequest?.respond(with: responseData)
                    loadingRequest.finishLoading()
                }
            } catch {
                print("HLS Gen Error: \(error)")
                self.updateDebugInfo("Err: \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
            }
        }
    }
    
    private func updateDebugInfo(_ info: String) {
        Task { @MainActor in
            self.debugInfo = info
            self.onDebugInfoUpdate?(info)
        }
    }
}
