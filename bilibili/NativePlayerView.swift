import SwiftUI
import AVKit

/// 一个基于 SwiftUI 原生 VideoPlayer 的播放器视图
/// 用于测试官方推荐的 Ornament 和沉浸式集成方案
struct NativePlayerView: View {
    let playInfo: BilibiliPlayerService.PlayInfo
    let cid: Int?
    let bvid: String?
    
    @StateObject private var playerModel = PlayerModel.shared
    @State private var showDanmaku = true
    @Environment(\.dismiss) private var dismiss
    
    // 沉浸模式相关
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isEnvironmentPickerPresented = false
    
    var body: some View {
        ZStack {
            if playerModel.isImmersiveMode {
                // 沉浸模式下：只显示一个极简的“退出”按钮，背景透明，让用户看到后方的 3D 屏幕
                VStack {
                    Spacer()
                    Button("退出影院模式") {
                        Task {
                            await dismissImmersiveSpace()
                            playerModel.isImmersiveMode = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .padding(.bottom, 50)
                }
            } else {
                if let player = playerModel.player {
                    // 使用 SwiftUI 原生 VideoPlayer
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .overlay {
                            // 弹幕层覆盖
                            if showDanmaku {
                                DanmakuView(engine: playerModel.danmakuEngine, player: player)
                                    .allowsHitTesting(false)
                            }
                        }
                } else {
                    ProgressView("正在加载...")
                }
            }
        }
        .background(playerModel.isImmersiveMode ? Color.clear : Color.black) // 沉浸模式下透明，防止遮挡 3D 场景
        // 左上角：原生风格的环境选择器
        .ornament(attachmentAnchor: .scene(.topLeading)) {
            HStack(spacing: 12) {
                // 返回
                Button {
                    playerModel.cleanup()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .hoverEffect()
                
                // 环境选择
                Button {
                    isEnvironmentPickerPresented.toggle()
                } label: {
                    Image(systemName: "mountains.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .hoverEffect()
                .popover(isPresented: $isEnvironmentPickerPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cinema 空间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        
                        Button {
                            isEnvironmentPickerPresented = false
                            Task {
                                await openImmersiveSpace(id: "ImmersiveCinema")
                                playerModel.isImmersiveMode = true
                                playerModel.shouldShowNativePlayer = false
                            }
                        } label: {
                            Label("影院", systemImage: "theatermasks.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                    .frame(width: 220)
                    .glassBackgroundEffect()
                }
            }
            .padding(.leading, 20)
            .padding(.top, 20)
        }
        // 底部：自定义控制条 (因为用了 VideoPlayer，我们可以选择隐藏自带的用自己的，或者共存)
        // 这里我们先只加一个弹幕开关演示
        .ornament(attachmentAnchor: .scene(.bottom)) {
            HStack {
                Toggle(isOn: $showDanmaku) {
                    Image(systemName: "text.bubble")
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .padding()
                .glassBackgroundEffect(in: Capsule())
            }
            .padding(.bottom, 20)
        }
        .task {
            await playerModel.loadVideo(playInfo: playInfo, cid: cid, bvid: bvid)
        }
        .onAppear {
            playerModel.isImmersiveMode = false
        }
        .onDisappear {
            // 简单清理
            if !playerModel.isImmersiveMode {
                playerModel.cleanup()
            }
        }
    }
}

