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
        // 如果需要沉浸式空间，可以在这里添加
        // .immersiveSpace(id: "ImmersiveSpace") { 
        //     ImmersiveView()
        // }
    }
}
