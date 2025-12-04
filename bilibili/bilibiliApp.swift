//
//  bilibiliApp.swift
//  bilibili
//
//  Created by 李谢坤 on 2025/5/27.
//

import SwiftUI

@main
struct bilibiliApp: App {
    init() {
        // 应用启动时预加载播放器组件
        Task { @MainActor in
            PlayerPreloader.shared.preload()
        }
    }
    
    var body: some Scene {
        WindowGroup(id: "MainWindow") {
            ContentView(viewModel: RecommendationViewModel())
                .environment(PlayerModel.shared)
        }
        
        WindowGroup(id: "PlayerWindow", for: String.self) { value in
            if let urlString = value.wrappedValue, let url = URL(string: urlString) {
                // 这里只是简单的 fallback，实际多窗口打开通常通过 VideoDetailView 的 fullScreenCover
                // 如果必须支持多窗口，需要重构数据传递方式
                let fallbackInfo = BilibiliPlayerService.PlayInfo(
                    source: .url(url),
                    quality: 0,
                    format: "mp4",
                    cid: nil
                )
                PlayerWindowView(playInfo: fallbackInfo, cid: nil, bvid: nil)
                    .environment(PlayerModel.shared)
            } else {
                Text("无效的播放地址")
            }
        }
        
        // 注册沉浸式影院空间
        ImmersiveSpace(id: "ImmersiveCinema") {
            CinemaView()
                .environment(PlayerModel.shared)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        
        // 注册演播室沉浸空间（用于官方 Demo 风格环境对比）
        ImmersiveSpace(id: "ImmersiveStudio") {
            StudioView()
                .environment(PlayerModel.shared)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
