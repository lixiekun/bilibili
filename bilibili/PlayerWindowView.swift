import SwiftUI
import AVKit

struct PlayerWindowView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var showOverlay = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if let player {
                PlayerControllerView(player: player)
                    .onDisappear {
                        stopAndCleanup()
                    }
                    .onTapGesture { showOverlay.toggle() }
            } else {
                ProgressView("正在加载播放器…")
            }

            if showOverlay {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            player?.play()
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            player?.pause()
                        } label: {
                            Image(systemName: "pause.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            stopAndCleanup()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
        }
        .task {
            await configurePlayer()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                stopAndCleanup()
            }
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

private struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
