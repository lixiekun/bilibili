//
//  bilibiliApp.swift
//  bilibili
//
//  Created by 李谢坤 on 2025/5/27.
//

import SwiftUI

@main
struct bilibiliApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: RecommendationViewModel())
        }
        WindowGroup(id: "PlayerWindow", for: String.self) { value in
            if let urlString = value.wrappedValue, let url = URL(string: urlString) {
                PlayerWindowView(url: url)
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
