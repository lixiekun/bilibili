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
        WindowGroup {
            ContentView(viewModel: RecommendationViewModel())
        }
        WindowGroup(id: "PlayerWindow", for: String.self) { value in
            if let urlString = value.wrappedValue, let url = URL(string: urlString) {
                // 这里只是简单的 fallback，实际多窗口打开通常通过 VideoDetailView 的 fullScreenCover
                // 如果必须支持多窗口，需要重构数据传递方式
                PlayerWindowView(playInfo: BilibiliPlayerService.PlayInfo(source: .url(url), quality: 0, format: "mp4"))
            } else {
                Text("无效的播放地址")
            }
        }
        // 如果需要沉浸式空间，可以在这里添加
        // .immersiveSpace(id: "ImmersiveSpace") { 
        //     ImmersiveView()
        // }
    }
}
