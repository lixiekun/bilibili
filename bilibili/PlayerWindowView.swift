import SwiftUI
import AVKit

struct PlayerWindowView: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView("正在加载播放器…")
            }

            // 自定义关闭按钮 - 悬浮在左上角
            VStack {
                HStack {
                    Button {
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
                    .padding(.leading, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                }
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
        player = AVPlayer(playerItem: item)
        player?.play()
    }

    private func stopAndCleanup() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}
