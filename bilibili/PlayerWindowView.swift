import SwiftUI
import AVKit
import Combine

struct PlayerWindowView: View {
    let playInfo: BilibiliPlayerService.PlayInfo
    let cid: Int?
    let bvid: String? // 新增 bvid，用于历史记录上报
    
    @State private var player: AVPlayer?
    @StateObject private var danmakuEngine = DanmakuEngine()
    @State private var showDanmaku = true
    @Environment(\.dismiss) private var dismiss
    
    // 用于保持 timer 的引用
    @State private var timeObserver: Any?
    
    // KSPlayer 状态
    // @State private var isKSPlaying = true

    init(playInfo: BilibiliPlayerService.PlayInfo, cid: Int? = nil, bvid: String? = nil) {
        self.playInfo = playInfo
        self.cid = cid
        self.bvid = bvid
    }

    var body: some View {
        ZStack {
            if let player {
                // 原生 AVPlayer 体验
                PlayerControllerView(player: player, danmakuEngine: danmakuEngine, showDanmaku: showDanmaku)
                    .ignoresSafeArea()
            } else {
                ProgressView("正在加载播放器…")
            }
            
            // 自定义控制层 (关闭按钮 + 弹幕开关)
            VStack {
                HStack {
                    // 关闭按钮
                    Button {
                        stopAndCleanup()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                    .background(.black.opacity(0.5), in: Circle())
                    .buttonStyle(.plain)
                    .hoverEffect()
                    
                    Spacer()
                    
                    // 清晰度调试信息
                    #if DEBUG
                    HStack(spacing: 4) {
                        Text("Q: \(playInfo.quality) | \(playInfo.format)")
                        if let delegate = resourceLoaderDelegate {
                            // Use a binding or just read the property.
                            // Since danmakuEngine updates frequently, this Text should refresh.
                            Text("| \(delegate.debugInfo)")
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    #endif
                    
                    Spacer()
                    
                    // 弹幕开关
                    Button {
                        showDanmaku.toggle()
                    } label: {
                        Image(systemName: showDanmaku ? "text.bubble.fill" : "text.bubble")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                    .background(.black.opacity(0.5), in: Circle())
                    .buttonStyle(.plain)
                    .hoverEffect()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
            }
        }
        .task {
            await configurePlayer()
        }
        .onDisappear {
            stopAndCleanup()
        }
    }

    private func configurePlayer() async {
        // 无论是 DASH 还是 URL 模式，都走统一的 createPlayer
        
        // 预先准备 headers (仅用于非 DASH)
        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Referer": "https://www.bilibili.com"
        ]
        if let cookies = HTTPCookieStorage.shared.cookies, !cookies.isEmpty {
            let cookieString = cookies.compactMap { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            headers["Cookie"] = cookieString
        }
        
        // 并行加载：同时创建播放器和加载弹幕
        // 注意：createPlayer 现在会处理 playInfo.source 的类型
        let currentURL: URL
        if case .url(let u) = playInfo.source {
            currentURL = u
        } else {
            // DASH 模式下，createPlayer 内部使用虚拟 URL，这里的 currentURL 仅作为占位
            currentURL = URL(string: "http://dummy")!
        }
        
        async let playerTask = createPlayer(url: currentURL, headers: headers)
        async let danmakuTask = loadDanmaku()
        
        // 等待播放器创建完成
        let newPlayer = await playerTask
        
        // 设置播放器
        self.player = newPlayer
        
        // 添加时间监听... (后续代码保持不变)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak danmakuEngine] time in
            let currentTime = time.seconds
            danmakuEngine?.update(currentTime: currentTime)
            
            // 历史记录上报 (每 15 秒)
            if Int(currentTime) > 0 && Int(currentTime) % 15 == 0 {
                if let bvid = bvid, let cid = cid {
                    Task {
                        await HistoryService.shared.reportProgress(bvid: bvid, cid: cid, progress: Int(currentTime), duration: 0)
                    }
                }
            }
        }
        
        // 开始播放
        newPlayer.play()
        
        // 等待弹幕加载完成（不阻塞播放）
        _ = await danmakuTask
    }
    
    @State private var resourceLoaderDelegate: BilibiliResourceLoaderDelegate?

    private func createPlayer(url: URL, headers: [String: String]) async -> AVPlayer {
        let asset: AVURLAsset
        
        // 判断是否为 DASH (通过判断 format 字段，或者 source 类型)
        if case .dash(let vInfo, let aInfo) = playInfo.source {
            // 构造自定义 Scheme 的 Master Playlist URL
            // 注意：这里实际上不需要真实的 URL，只要是 custom-scheme 即可触发 delegate
            let masterURL = URL(string: "custom-scheme://playlist/master.m3u8")!
            // 关键修改：传入 headers options，确保后续 HTTP 请求带上 Referer
            asset = AVURLAsset(url: masterURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            
            // 初始化 Delegate (强引用，否则会被释放)
            let delegate = BilibiliResourceLoaderDelegate(videoInfo: vInfo, audioInfo: aInfo)
            self.resourceLoaderDelegate = delegate
            
            // 设置 Delegate
            asset.resourceLoader.setDelegate(delegate, queue: .main)
        } else {
            // 普通 HLS/MP4
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        
        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = 0 // 0 表示不限制，保持源码率
        
        // 预加载关键属性，加快播放器初始化
        item.automaticallyHandlesInterstitialEvents = true
        
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        
        return newPlayer
    }
    
    private func loadDanmaku() async {
        guard let cid = cid else { return }
        
        do {
            print("开始加载弹幕 CID: \(cid)")
            let danmakus = try await DanmakuService().fetchDanmaku(cid: cid)
            print("弹幕加载成功，共 \(danmakus.count) 条")
            await MainActor.run {
                danmakuEngine.load(danmakus: danmakus)
            }
        } catch {
            print("弹幕加载失败: \(error)")
        }
    }

    private func stopAndCleanup() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        timeObserver = nil
    }
}

private struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer
    @ObservedObject var danmakuEngine: DanmakuEngine
    let showDanmaku: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        
        // 创建弹幕层控制器
        // 注意：这里需要一个新的 UIHostingController 来承载 DanmakuView
        let danmakuView = DanmakuView(engine: danmakuEngine, player: player)
        let hostingController = UIHostingController(rootView: danmakuView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        
        // 关键：禁用 hosting view 的用户交互，让点击穿透到底下的视频控制层
        // 如果需要弹幕交互（如点赞弹幕），则需要更精细的 HitTest 处理
        hostingController.view.isUserInteractionEnabled = false 

        // 保存到 coordinator
        context.coordinator.danmakuController = hostingController
        
        // 添加到 contentOverlayView
        // contentOverlayView 是专门用于在视频内容和控件之间添加自定义视图的层级
        if let contentOverlay = vc.contentOverlayView {
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            contentOverlay.addSubview(hostingController.view)
            
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: contentOverlay.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: contentOverlay.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: contentOverlay.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: contentOverlay.trailingAnchor)
            ])
            
            // 必须调用 didMove，完成子控制器的添加流程（虽然我们没有显式 addChildViewController）
            // 严格来说应该 vc.addChild(hostingController)，但 AVPlayerViewController 可能有限制
            // 仅仅 addSubview 通常足够用于 overlay
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // 更新 player (如果变了)
        if uiViewController.player != player {
            uiViewController.player = player
        }
        
        // 控制弹幕层显示/隐藏
        context.coordinator.danmakuController?.view.isHidden = !showDanmaku
        
        // 如果需要更新 DanmakuView 的参数（例如 player 变了），可能需要重新设置 rootView
        // 但由于 Engine 和 Player 是引用类型，且 Engine 是 ObservedObject，View 应该会自动更新
        // 这里主要控制 isHidden
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var danmakuController: UIHostingController<DanmakuView>?
    }
}
