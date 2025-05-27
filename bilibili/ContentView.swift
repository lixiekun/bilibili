//
//  ContentView.swift
//  bilibili
//
//  Created by 李谢坤 on 2025/5/27.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @StateObject private var viewModel = RecommendationViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationView { // visionOS 中通常使用 NavigationView
                VStack {
                    if viewModel.isLoading {
                        ProgressView("正在加载推荐...")
                    } else if let errorMessage = viewModel.errorMessage {
                        Text("错误: \(errorMessage)")
                            .foregroundColor(.red)
                        Button("重试") {
                            viewModel.fetchRecommendations()
                        }
                    } else {
                        List(viewModel.videoItems) { item in
                            VideoRow(videoItem: item)
                        }
                        .navigationTitle("首页推荐")
                    }
                }
                .onAppear {
                    viewModel.fetchRecommendations() // 视图出现时获取数据
                }
            }
        }
    }
}

// 单独的行视图，用于展示每个视频的信息
struct VideoRow: View {
    let videoItem: VideoItem

    var body: some View {
        HStack {
            // 使用 AsyncImage (iOS 15+/macOS 12+/watchOS 8+/tvOS 15+) 加载网络图片
            // 对于 visionOS，这是可用的
            AsyncImage(url: URL(string: videoItem.coverImageURL)) {
                phase in
                if let image = phase.image {
                    image.resizable()
                         .aspectRatio(contentMode: .fit)
                         .frame(width: 120, height: 70) // 调整封面大小
                         .cornerRadius(8)
                } else if phase.error != nil {
                    Image(systemName: "photo") // 加载失败时的占位图
                        .frame(width: 120, height: 70)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    ProgressView() // 加载中的占位图
                        .frame(width: 120, height: 70)
                }
            }

            VStack(alignment: .leading) {
                Text(videoItem.title)
                    .font(.headline)
                    .lineLimit(2) // 限制标题行数
                Text(videoItem.authorName)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer() // 把内容推到左边
        }
    }
}

#Preview {
    ContentView()
}
