import SwiftUI
import RealityKit
import AVKit
import Observation

/// 用于标记当前屏幕绑定的 AVPlayer，避免在 RealityKit 更新循环中重复创建 VideoMaterial。
struct PlayerBindingComponent: Component {
    var playerID: ObjectIdentifier
}

private let cinemaScreenWidth: Float = 10.0
private let cinemaScreenAspect: Float = 16.0 / 9.0
private let cinemaScreenHeight: Float = cinemaScreenWidth / cinemaScreenAspect
private let controlsDragToMeter: Float = 800.0

struct CinemaView: View {
    @Environment(PlayerModel.self) private var playerModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    
    // 交互状态
    @State private var scale: CGFloat = 1.0
    @State private var distance: CGFloat = -9.0 // 默认推远一点，营造大屏感
    @State private var lastScale: CGFloat = 1.0
    @State private var lastDistance: CGFloat = -9.0
    @State private var isControlsVisible: Bool = true // 控制面板可见性（默认显示）
    @State private var isDisplaySettingsVisible: Bool = false // 显示设置面板可见性
    @State private var isDanmakuVisible: Bool = true // 弹幕可见性
    
    // 控制面板位置偏移 (用于拖拽移动)
    @State private var controlsOffset: CGPoint = .zero

    var body: some View {
        RealityView { content, attachments in
            // 创建一个 TheaterRoot 节点，包含屏幕和背景墙
            let theaterRoot = Entity()
            theaterRoot.name = "TheaterRoot"
            theaterRoot.position = [0, 1.5, Float(distance)]
            content.add(theaterRoot)
            
            // 1. 创建虚拟屏幕 (即背景墙)
            // 初始尺寸可以设大一点，后续会动态调整
            // 将 cornerRadius 设置为 0 以去除圆角
            let screenMesh = MeshResource.generatePlane(width: cinemaScreenWidth, height: cinemaScreenHeight, cornerRadius: 0.0)
            let screenEntity = ModelEntity(mesh: screenMesh)
            screenEntity.name = "Screen"
            screenEntity.position = [0, 0, 0] // 相对于 TheaterRoot
            
            // 添加碰撞体和输入目标，以便支持手势
            screenEntity.generateCollisionShapes(recursive: false)
            screenEntity.components.set(InputTargetComponent())
            
            // 创建 VideoMaterial
            // 注意：AVPlayer 必须在 RealityView 更新之前准备好
            // 如果 playerModel.player 发生变化，我们需要确保 material 也更新
            // 但 RealityView 的 make 只执行一次。
            // 我们在 update 中处理 material 的更新会更稳妥，或者在这里先设置一个，如果为空后续补上。
            // 关键修复：CinemaView 初始化时 player 可能已经存在，或者随后加载。
            // 我们必须确保 VideoMaterial 绑定的是最新的 player。
            
            if let player = playerModel.player {
                let material = VideoMaterial(avPlayer: player)
                screenEntity.model?.materials = [material]
            } else {
                // 占位黑色材质
                let material = SimpleMaterial(color: .black, isMetallic: false)
                screenEntity.model?.materials = [material]
            }
            
            theaterRoot.addChild(screenEntity)
            
            // 3. 添加控制层 Attachment (保持在 content 下，固定在用户身边)
            if let controls = attachments.entity(for: "controls") {
                // 将控制面板放在用户身边 (假设用户在原点，向前0.8米，高度1.1米)
                // 不添加到 rootEntity，而是直接添加到 content，使其位置固定，不随屏幕缩放/移动
                controls.position = [0, 1.1, -0.8]
                controls.name = "ControlsLayer"
                content.add(controls)
                controls.isEnabled = isControlsVisible // 初始状态
            }
            
            // 4. 添加弹幕层 Attachment
            if let danmaku = attachments.entity(for: "danmaku") {
                // 弹幕层必须作为屏幕的子节点，这样才能跟随屏幕一起移动和缩放
                // 重置位置为相对于屏幕的偏移（稍微靠前一点防止 Z-fighting）
                danmaku.position = [0, 0, 0.01]
                danmaku.name = "DanmakuLayer"
                
                // 确保添加到 screenEntity 下，而不是 rootEntity
                // 先找到 screenEntity
                if let screen = theaterRoot.findEntity(named: "Screen") {
                    screen.addChild(danmaku)
                }
            }
            
        } update: { content, _ in
            guard let theaterRoot = content.entities.first(where: { $0.name == "TheaterRoot" }) else { return }
            
            // 更新 TheaterRoot 位置 (距离)
                theaterRoot.position.z = Float(distance)
            
            if let screen = theaterRoot.findEntity(named: "Screen"),
               let modelEntity = screen as? ModelEntity {
                
                var scaleYCorrection: Float = 1.0
                
                if let player = playerModel.player {
                    let newID = ObjectIdentifier(player)
                    let currentID = modelEntity.components[PlayerBindingComponent.self]?.playerID
                    if currentID != newID {
                        let material = VideoMaterial(avPlayer: player)
                        modelEntity.model?.materials = [material]
                        modelEntity.components.set(PlayerBindingComponent(playerID: newID))
                    }
                    
                    if let currentItem = player.currentItem {
                        let size = currentItem.presentationSize
                        if size.width > 0 && size.height > 0 {
                            let videoAspect = size.width / size.height
                            let baseAspect = CGFloat(cinemaScreenWidth / cinemaScreenHeight)
                            let correction = Float(baseAspect / videoAspect)
                            scaleYCorrection = max(0.2, min(5.0, correction))
                        }
                    }
                } else {
                    if !(modelEntity.model?.materials.first is SimpleMaterial) {
                        modelEntity.model?.materials = [SimpleMaterial(color: .black, isMetallic: false)]
                    }
                    modelEntity.components.remove(PlayerBindingComponent.self)
                }
                
                // 更新屏幕缩放（Y 根据视频宽高比调整）
                modelEntity.scale = [
                    Float(scale),
                    Float(scale) * scaleYCorrection,
                    Float(scale)
                ]
                
                // 更新弹幕层可见性及尺寸
                if let danmaku = modelEntity.findEntity(named: "DanmakuLayer") {
                    danmaku.isEnabled = isDanmakuVisible
                    let bounds = danmaku.visualBounds(relativeTo: danmaku)
                    let localWidth = bounds.extents.x
                    if localWidth > 0 {
                        let s = cinemaScreenWidth / localWidth
                        if abs(danmaku.scale.x - s) > 0.001 {
                            danmaku.scale = [s, s, s]
                        }
                    }
                }
            }
            
            // 更新控制层可见性与位置
            if let controls = content.entities.first(where: { $0.name == "ControlsLayer" }) {
                controls.isEnabled = isControlsVisible
                let x = Float(controlsOffset.x) / controlsDragToMeter
                let y = Float(-controlsOffset.y) / controlsDragToMeter
                controls.position = [x, 1.1 + y, -0.8]
            }
            
        } attachments: {
            Attachment(id: "controls") {
                CinemaControlsView(
                    player: playerModel.player,
                    distance: $distance,
                    scale: $scale,
                    isDanmakuVisible: $isDanmakuVisible,
                    dragOffset: $controlsOffset,
                    onExit: {
                        Task {
                            await dismissImmersiveSpace()
                            playerModel.isImmersiveMode = false
                            
                            // 确保 ContentView 能恢复到当前视频的详情页
                            // 如果 restoringVideoItem 未设置（例如从 Window 播放器进入），则使用当前视频
                            if playerModel.restoringVideoItem == nil {
                                playerModel.restoringVideoItem = playerModel.currentVideoItem
                            }
                            
                            // 退出后暂停，但保留播放器，便于再次进入沉浸模式时直接复用
                            playerModel.player?.pause()
                            // 退出沉浸模式后，重新打开主窗口 (详情页)
                            openWindow(id: "MainWindow")
                        }
                    }
                )
                .frame(width: 600)
            }
            
            Attachment(id: "danmaku") {
                DanmakuView(engine: playerModel.danmakuEngine, player: playerModel.player)
                    .frame(width: 1920, height: 1080)
                    .allowsHitTesting(false)
            }
        }
        // 仅对影院屏幕实体添加点击手势，避免拦截控制面板的互动
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if value.entity.name == "Screen" || value.entity.name == "TheaterRoot" {
                        withAnimation(.easeInOut) {
                            isControlsVisible.toggle()
                        }
                    }
                }
        )
        .onAppear {
            print("🎬 CinemaView onAppear")
            // 确保沉浸模式状态正确
            playerModel.isImmersiveMode = true
            
            // 如果因为退出时清理了播放器，重新进入时确保重新加载
            if playerModel.player == nil, let info = playerModel.playInfo {
                Task {
                    await playerModel.loadVideo(playInfo: info, cid: playerModel.cid, bvid: playerModel.bvid)
                    playerModel.player?.play()
                }
            }
            // 注意：不在这里关闭 PlayerWindow，由 PlayerWindowView 自己处理
        }
        .onDisappear {
            // 任何途径退出沉浸空间都复位状态，避免下一次无法重新进入
            playerModel.isImmersiveMode = false
        }
    }
}
struct CinemaControlsView: View {
    let player: AVPlayer?
    @Binding var distance: CGFloat
    @Binding var scale: CGFloat
    @Binding var isDanmakuVisible: Bool
    @Binding var dragOffset: CGPoint // 拖拽偏移量
    let onExit: () -> Void
    
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var isDraggingSlider: Bool = false
    @State private var showDisplaySettings: Bool = false
    @State private var dragStartOffset: CGPoint? = nil
    
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        HStack {
                            Text(formatTime(currentTime))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatTime(duration))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        
                        ImmersiveProgressBar(
                            currentTime: $currentTime,
                            duration: duration,
                            isDragging: $isDraggingSlider,
                            onSeek: { newValue in
                                seek(to: newValue)
                            }
                        )
                        .frame(height: 32)
                    }
                    
                    DistanceControlBar(distance: $distance)
                        .frame(height: 32)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .glassBackgroundEffect()
                
                // 按钮行
                HStack(spacing: 40) {
                    // 退出按钮
                    Button(action: onExit) {
                        Image(systemName: "xmark")
                            .font(.title2)
                    }
                    .buttonStyle(.plain) // 使用 plain 风格配合 glassBackground
                    .padding(12)
                    .glassBackgroundEffect(displayMode: .always)
                    .clipShape(Circle())
                    .help("退出沉浸模式")
                    
                    // 快退
                Button {
                    seek(to: currentTime - 15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                    .buttonStyle(.plain)
                    .padding(12)
                    .glassBackgroundEffect(displayMode: .always)
                    .clipShape(Circle())
                
                    // 播放/暂停
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                            .frame(width: 32, height: 32) // 统一图标视觉大小
                }
                    .buttonStyle(.plain)
                    .padding(20)
                    .glassBackgroundEffect(displayMode: .always)
                    .clipShape(Circle())
                
                    // 快进
                Button {
                    seek(to: currentTime + 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                    .buttonStyle(.plain)
                    .padding(12)
                    .glassBackgroundEffect(displayMode: .always)
                    .clipShape(Circle())
                
                    // 更多设置 (包含距离、大小、弹幕)
                Button {
                    withAnimation {
                        showDisplaySettings.toggle()
                    }
                } label: {
                        Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                }
                    .buttonStyle(.plain)
                    .padding(12)
                    .glassBackgroundEffect(displayMode: .always)
                    .clipShape(Circle())
                .background(showDisplaySettings ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(Circle())
            }
            
                // 显示设置面板
            if showDisplaySettings {
                VStack(spacing: 16) {
                        // 弹幕开关
                        Toggle(isOn: $isDanmakuVisible) {
                            Label("显示弹幕", systemImage: isDanmakuVisible ? "captions.bubble.fill" : "captions.bubble")
                                .font(.headline)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)
                        
                    Divider()
                        .overlay(Color.white.opacity(0.2))
                    
                        // 距离控制
                    HStack {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .frame(width: 24)
                            Text("距离")
                                .font(.caption)
                            Slider(value: $distance, in: -12.0...(-1.5))
                        Text("\(abs(distance), specifier: "%.1f")m")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    
                        // 大小控制
                    HStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                 .frame(width: 24)
                            Text("大小")
                                .font(.caption)
                            Slider(value: $scale, in: 0.5...3.0)
                        Text("\(scale, specifier: "%.1f")x")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                    .padding(20)
                    .glassBackgroundEffect() // 单独的磨砂背景
                    .frame(width: 400) // 限制宽度
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(24)
        .glassBackgroundEffect()
            
            // 拖拽手柄 Bar (在主面板下方)
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 120, height: 6)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragStartOffset == nil {
                                dragStartOffset = dragOffset
                            }
                            let base = dragStartOffset ?? .zero
                            dragOffset = CGPoint(
                                x: base.x + value.translation.width,
                                y: base.y + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStartOffset = nil
                        }
                )
        }
        .onReceive(timer) { _ in
            guard !isDraggingSlider, let player = player else { return }
            isPlaying = player.timeControlStatus == .playing
            currentTime = player.currentTime().seconds
            if let item = player.currentItem {
                duration = item.duration.seconds
                if duration.isNaN { duration = 1 }
            }
        }
    }
    
    private func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    private func seek(to time: Double) {
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: targetTime)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

private struct ImmersiveProgressBar: View {
    @Binding var currentTime: Double
    let duration: Double
    @Binding var isDragging: Bool
    let onSeek: (Double) -> Void
    
    private let knobSize: CGFloat = 14
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let trackHeight: CGFloat = 8
            let safeDuration = max(duration, 0.0001)
            let ratio = max(0, min(1, currentTime / safeDuration))
            let progressWidth = width * ratio
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                    )
                    .frame(height: trackHeight)
                
                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.55)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(progressWidth, knobSize / 2), height: trackHeight)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .offset(x: max(min(progressWidth - knobSize / 2, width - knobSize), 0), y: -(knobSize - trackHeight) / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = max(0, min(width, value.location.x))
                        let newRatio = x / width
                        let newTime = safeDuration * newRatio
                        isDragging = true
                        currentTime = newTime
                    }
                    .onEnded { value in
                        let x = max(0, min(width, value.location.x))
                        let newRatio = x / width
                        let newTime = safeDuration * newRatio
                        currentTime = newTime
                        isDragging = false
                        onSeek(newTime)
                    }
            )
        }
        .animation(.easeOut(duration: 0.12), value: currentTime)
    }
}

private struct DistanceControlBar: View {
    @Binding var distance: CGFloat
    private let range: ClosedRange<CGFloat> = -12.0...(-1.5)
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let normalized = (distance - range.lowerBound) / (range.upperBound - range.lowerBound)
            let knobSize: CGFloat = 18
            let trackHeight: CGFloat = 10
            let ratio = max(0, min(1, normalized))
            let knobX = ratio * width
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .frame(height: trackHeight)
                    .allowsHitTesting(false)
                
                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .fill(
                        LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.35)],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .frame(width: max(knobX, knobSize / 2), height: trackHeight)
                    .allowsHitTesting(false)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
                    .offset(x: max(min(knobX - knobSize / 2, width - knobSize), 0), y: -4)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { distance },
                        set: { distance = min(max($0, range.lowerBound), range.upperBound) }
                    ),
                    in: range
                )
                .tint(.clear)
                .labelsHidden()
                .opacity(0.02)
            }
        }
    }
}
