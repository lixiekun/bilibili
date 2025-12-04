import Foundation
import AVKit
import Observation

enum PresentationMode {
    case inline
    case immersive
}

/// 播放器状态管理模型
/// 负责持有 AVPlayer 和 DanmakuEngine，以便在 Window 和 ImmersiveSpace 之间共享状态
@Observable
@MainActor
class PlayerModel {
    static let shared = PlayerModel()
    
    var player: AVPlayer?
    var danmakuEngine = DanmakuEngine()
    var playInfo: BilibiliPlayerService.PlayInfo?
    var cid: Int?
    var bvid: String?
    var resourceLoaderDelegate: BilibiliResourceLoaderDelegate?
    var isImmersiveMode: Bool = false {
        didSet {
            print("PlayerModel: isImmersiveMode changed from \(oldValue) to \(isImmersiveMode)")
        }
    }
    var shouldShowNativePlayer: Bool = false // 全局控制 2D 播放器显示状态
    var restoringVideoItem: VideoItem? // 用于在退出沉浸模式时恢复详情页
    var shouldEnterCinema: Bool = false // 触发进入影院模式（用于 immersiveEnvironmentPicker）
    var shouldDismissPlayerWindow: Bool = false // 触发关闭 PlayerWindowView 的 fullScreenCover
    var isWindowPlayerPresented: Bool = false // 全局控制 PlayerWindowView 的 fullScreenCover 显示状态
    var currentVideoItem: VideoItem? // 当前播放的视频信息，用于 ZStack 播放器构建
    var presentation: PresentationMode = .inline {
        didSet {
            print("PlayerModel: presentation changed from \(oldValue) to \(presentation)")
            let immersive = presentation == .immersive
            if isImmersiveMode != immersive {
                isImmersiveMode = immersive
            }
        }
    }

    // 用于控制播放器的时间监听器
    var timeObserver: Any?
    
    private init() {}
    
    /// 标记进入沉浸模式，统一隐藏窗口播放器但保留 AVPlayer。
    func beginImmersiveSession() {
        presentation = .immersive
        shouldDismissPlayerWindow = true
        isWindowPlayerPresented = false
    }
    
    /// 退出沉浸模式后恢复窗口播放器的显示与播放。
    func endImmersiveSession(resumePlayback: Bool = true) {
        presentation = .inline
        if restoringVideoItem == nil {
            restoringVideoItem = currentVideoItem
        }
        if resumePlayback {
            player?.play()
        }
        isWindowPlayerPresented = true
        shouldDismissPlayerWindow = false
    }
    
    /// 加载视频
    func loadVideo(playInfo: BilibiliPlayerService.PlayInfo, cid: Int?, bvid: String?) async {
        // 如果已经在播放同一个视频，就不重新加载
        if let currentCid = self.cid, currentCid == cid, player != nil {
            return
        }
        
        cleanup()
        
        self.playInfo = playInfo
        let resolvedCid = cid ?? playInfo.cid
        self.cid = resolvedCid
        self.bvid = bvid
        
        // 预先准备 headers
        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Referer": "https://www.bilibili.com"
        ]
        if let cookies = HTTPCookieStorage.shared.cookies, !cookies.isEmpty {
            let cookieString = cookies.compactMap { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            headers["Cookie"] = cookieString
        }
        
        // 创建播放器
        let currentURL: URL
        if case .url(let u) = playInfo.source {
            currentURL = u
        } else {
            currentURL = URL(string: "http://dummy")!
        }
        
        await createPlayer(url: currentURL, headers: headers, playInfo: playInfo)
        
        // 加载弹幕
        if let resolvedCid {
            await loadDanmaku(cid: resolvedCid)
        } else {
            danmakuEngine.load(danmakus: [])
        }
    }
    
    private func createPlayer(url: URL, headers: [String: String], playInfo: BilibiliPlayerService.PlayInfo) async {
        let asset: AVURLAsset
        
        if case .dash(let vInfo, let aInfo) = playInfo.source {
            let masterURL = URL(string: "custom-scheme://playlist/master.m3u8")!
            asset = AVURLAsset(url: masterURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            
            let delegate = BilibiliResourceLoaderDelegate(videoInfo: vInfo, audioInfo: aInfo)
            self.resourceLoaderDelegate = delegate
            asset.resourceLoader.setDelegate(delegate, queue: .main)
        } else {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        
        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = 0
        item.automaticallyHandlesInterstitialEvents = true
        
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        
        self.player = newPlayer
        
        // 添加时间监听
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let currentTime = time.seconds
                self.danmakuEngine.update(currentTime: currentTime)
                
                if Int(currentTime) > 0 && Int(currentTime) % 15 == 0 {
                    if let bvid = self.bvid, let cid = self.cid {
                        Task.detached {
                            await HistoryService.shared.reportProgress(bvid: bvid, cid: cid, progress: Int(currentTime), duration: 0)
                        }
                    }
                }
            }
        }
        
        newPlayer.play()
    }
    
    private func loadDanmaku(cid: Int) async {
        do {
            print("PlayerModel: 开始加载弹幕 CID: \(cid)")
            let estimatedDuration = 3600 
            let danmakus = try await DanmakuService().fetchDanmaku(cid: cid, duration: estimatedDuration)
            print("PlayerModel: 弹幕加载成功，共 \(danmakus.count) 条")
            danmakuEngine.load(danmakus: danmakus)
        } catch {
            print("PlayerModel: 弹幕加载失败: \(error)")
        }
    }
    
    func cleanup() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        timeObserver = nil
        resourceLoaderDelegate = nil
        danmakuEngine.activeDanmakus = []
    }
}
