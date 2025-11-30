import SwiftUI
import AVKit
import Combine

struct PlayerWindowView: View {
    let url: URL
    let cid: Int?
    let bvid: String? // 新增 bvid，用于历史记录上报
    
    @State private var player: AVPlayer?
    @StateObject private var danmakuEngine = DanmakuEngine()
    @State private var showDanmaku = true
    @Environment(\.dismiss) private var dismiss
    
    // 用于保持 timer 的引用
    @State private var timeObserver: Any?

    init(url: URL, cid: Int? = nil, bvid: String? = nil) {
        self.url = url
        self.cid = cid
        self.bvid = bvid
    }

    var body: some View {
        ZStack {
            if let player {
                // 使用原生 AVPlayerViewController 并通过 contentOverlayView 注入弹幕
                // 这样可以获得原生的播放控制体验，同时避免遮挡
                PlayerControllerView(player: player, danmakuEngine: danmakuEngine, showDanmaku: showDanmaku)
                    .ignoresSafeArea()
            } else {
                ProgressView("正在加载播放器…")
            }

            // 自定义控制层 (关闭按钮 + 弹幕开关)
            // 注意：由于 AVPlayerViewController 会接管手势，这些按钮可能需要放在 contentOverlayView 里
            // 或者放在 ZStack 的最上层，但要确保不遮挡播放器控件
            // 目前先保留在这里，如果点击不灵敏，可以考虑也移入 contentOverlayView
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
        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            "Referer": "https://www.bilibili.com"
        ]
        if let cookies = HTTPCookieStorage.shared.cookies, !cookies.isEmpty {
            let cookieString = cookies.compactMap { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            headers["Cookie"] = cookieString
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = 0 // 0 表示不限制，保持源码率
        let newPlayer = AVPlayer(playerItem: item)
        
        // 添加时间监听，每 0.1 秒更新一次弹幕引擎，并定期上报历史记录
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
        
        self.player = newPlayer
        newPlayer.play()
        
        // 加载弹幕数据
        if let cid = cid {
            Task {
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
