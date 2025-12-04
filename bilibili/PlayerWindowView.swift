import SwiftUI
import AVKit
import Combine
import os.log

// 创建一个专用的 Logger
private let logger = Logger(subsystem: "com.bilibili.app", category: "PlayerWindow")

// 用于跨视图通信的通知名称
extension Notification.Name {
    static let enterCinemaMode = Notification.Name("enterCinemaMode")
    static let enterStudioMode = Notification.Name("enterStudioMode")
}

struct PlayerWindowView: View {
    let playInfo: BilibiliPlayerService.PlayInfo
    let cid: Int?
    let bvid: String?
    
    @StateObject private var playerModel = PlayerModel.shared
    @State private var showDanmaku = true
    @State private var isEnteringImmersive = false  // 防止重复调用
    @Environment(\.dismiss) private var dismiss
    
    // 沉浸模式相关
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    init(playInfo: BilibiliPlayerService.PlayInfo, cid: Int? = nil, bvid: String? = nil) {
        self.playInfo = playInfo
        self.cid = cid
        self.bvid = bvid
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let player = playerModel.player {
                PlayerControllerView(
                    player: player,
                    danmakuEngine: playerModel.danmakuEngine,
                    showDanmaku: showDanmaku,
                    onClose: {
                        print("🎬 PlayerWindowView: onClose callback")
                        closePlayer()
                    }
                )
                .ignoresSafeArea()
                // 使用系统自带的 immersiveEnvironmentPicker 添加自定义影院场景
                .immersiveEnvironmentPicker {
                    ImmersiveEnvironmentPickerView()
                }
            } else {
                ProgressView("正在加载播放器…")
            }
            

        }
        .task {
            await playerModel.loadVideo(playInfo: playInfo, cid: cid, bvid: bvid)
        }
        // 监听通知
        .onReceive(NotificationCenter.default.publisher(for: .enterCinemaMode)) { _ in
            print("📢 收到 enterCinemaMode 通知!")
            enterImmersiveSpace(id: "ImmersiveCinema")
        }
        .onReceive(NotificationCenter.default.publisher(for: .enterStudioMode)) { _ in
            print("📢 收到 enterStudioMode 通知!")
            enterImmersiveSpace(id: "ImmersiveStudio")
        }
        .onDisappear {
            print("🎬 PlayerWindowView onDisappear. model immersive: \(playerModel.isImmersiveMode)")
            // 只有在不是因为进入沉浸模式而消失时，才清理播放器
            if !playerModel.isImmersiveMode {
                print("🎬 非沉浸模式退出，清理播放器资源")
                playerModel.cleanup()
            }
        }
    }
    
    /// 进入指定沉浸空间
    private func enterImmersiveSpace(id: String) {
        // 防止重复调用
        guard !isEnteringImmersive else {
            print("🎬 已在进入沉浸模式中，忽略重复调用")
            return
        }
        isEnteringImmersive = true
        
        Task { @MainActor in
            print("🎬 准备进入沉浸空间 \(id)...")
            
            // 1. 确保视频数据已加载
            await playerModel.loadVideo(playInfo: playInfo, cid: cid, bvid: bvid)
            playerModel.player?.play() // 再次进入时确保播放器已启动
            
            // 2. 设置状态
            playerModel.isImmersiveMode = true
            
            // 3. 打开沉浸空间
            print("🎬 打开沉浸空间...")
            let result = await openImmersiveSpace(id: id)
            print("🎬 沉浸空间 \(id) 打开结果: \(result)")
            
            // 4. 只有成功打开时才关闭窗口
            if case .opened = result {
                print("🎬 沉浸空间已打开，关闭播放器窗口...")
                // 通知 ContentView 关闭 fullScreenCover
                playerModel.shouldDismissPlayerWindow = true
                // 同时尝试关闭 Window（如果是通过 WindowGroup 打开的）
                dismissWindow(id: "PlayerWindow")
                dismiss()
            } else {
                print("🎬 沉浸空间打开失败，保持当前窗口")
                playerModel.isImmersiveMode = false
                isEnteringImmersive = false
            }

            // 成功或失败都需要复位标识，避免下一次无法进入
            if case .opened = result {
                isEnteringImmersive = false
            }
        }
    }
    
    private func closePlayer() {
        print("🎬 PlayerWindowView: closePlayer() called")
        if playerModel.isImmersiveMode {
            print("🎬 closePlayer: currently in immersive mode, skip cleanup")
        } else {
            playerModel.cleanup()
        }
        playerModel.isWindowPlayerPresented = false
        playerModel.shouldDismissPlayerWindow = true
        dismiss()
    }
}

/// 自定义环境选择器内容视图
/// 此视图的内容会显示在 AVPlayerViewController 系统环境选择器中
/// 参考: https://developer.apple.com/documentation/visionOS/building-an-immersive-media-viewing-experience
private struct ImmersiveEnvironmentPickerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 影院场景按钮 - 显示在系统环境选项旁边
            Button {
                print("🎬 immersiveEnvironmentPicker 影院按钮被点击!")
                NotificationCenter.default.post(name: .enterCinemaMode, object: nil)
            } label: {
                Label {
                    Text("影院")
                } icon: {
                    Image(systemName: "theatermasks.fill")
                }
                Text("沉浸式影院")
            }
            
            Button {
                print("🎬 immersiveEnvironmentPicker Studio 按钮被点击!")
                NotificationCenter.default.post(name: .enterStudioMode, object: nil)
            } label: {
                Label {
                    Text("演播室")
                } icon: {
                    Image(systemName: "lightbulb.3.fill")
                }
                Text("沉浸式演播室")
            }
        }
        .onAppear {
            print("🎬 ImmersiveEnvironmentPickerView onAppear")
        }
    }
}

/// AVPlayerViewController 的 SwiftUI 包装器
struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer
    @ObservedObject var danmakuEngine: DanmakuEngine
    let showDanmaku: Bool
    let onClose: () -> Void // 添加关闭回调

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.delegate = context.coordinator // 关键：设置 delegate 才能收到回调
        
        // 不使用 contextualActions，只依赖系统的 immersiveEnvironmentPicker
        
        // 创建弹幕层控制器
        let danmakuView = DanmakuView(engine: danmakuEngine, player: player)
        let hostingController = UIHostingController(rootView: danmakuView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.isUserInteractionEnabled = false 

        context.coordinator.danmakuController = hostingController
        
        if let contentOverlay = vc.contentOverlayView {
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            contentOverlay.addSubview(hostingController.view)
            
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: contentOverlay.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: contentOverlay.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: contentOverlay.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: contentOverlay.trailingAnchor)
            ])
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player != player {
            uiViewController.player = player
        }
        context.coordinator.danmakuController?.view.isHidden = !showDanmaku
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var parent: PlayerControllerView
        var danmakuController: UIHostingController<DanmakuView>?
        
        init(_ parent: PlayerControllerView) {
            self.parent = parent
        }
        
        // 监听播放器即将关闭/返回的事件 (visionOS 上通常是用户点击了左上角的关闭或返回)
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            print("🎬 AVPlayerViewController willEndFullScreenPresentation")
            // 这里是系统全屏退出的回调，虽然我们主要用 inline/custom 模式，但如果用户触发了系统的退出手势
            parent.onClose()
        }
    }
}
