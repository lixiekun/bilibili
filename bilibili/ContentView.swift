//
//  ContentView.swift
//  bilibili
//
//  Created by 李谢坤 on 2025/5/27.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RecommendationViewModel()
    @State private var selection: VideoItem?

    var body: some View {
        NavigationSplitView {
            Group {
                if viewModel.isLoading {
                    ProgressView("正在加载推荐…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Text("错误: \(errorMessage)")
                            .foregroundColor(.red)
                        Button("重试") {
                            viewModel.fetchRecommendations()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.videoItems.isEmpty {
                    Text("暂无推荐内容")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.videoItems, selection: $selection) { item in
                        VideoRow(videoItem: item)
                            .tag(item)
                    }
                    .navigationTitle("首页推荐")
                    .toolbar {
                        Button("刷新") {
                            viewModel.fetchRecommendations()
                        }
                    }
                }
            }
        } detail: {
            if let selected = selection ?? viewModel.videoItems.first {
                VideoDetailView(videoItem: selected)
                    .navigationTitle(selected.title)
            } else {
                Text("选择一个视频查看详情")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            viewModel.fetchRecommendations()
        }
        .onChange(of: viewModel.videoItems) { newItems in
            if selection == nil {
                selection = newItems.first
            }
        }
    }
}

struct VideoRow: View {
    let videoItem: VideoItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: videoItem.coverImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 80)
                        .clipped()
                        .cornerRadius(10)
                case .failure:
                    Image(systemName: "photo")
                        .frame(width: 140, height: 80)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                case .empty:
                    ProgressView()
                        .frame(width: 140, height: 80)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(videoItem.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(videoItem.authorName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(videoItem.viewCount.formatted(.number.notation(.compactName))) 次观看 · \(formattedDuration(videoItem.duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct VideoDetailView: View {
    let videoItem: VideoItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: videoItem.coverImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(16)
                    case .failure:
                        Image(systemName: "photo")
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    @unknown default:
                        EmptyView()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(videoItem.title)
                        .font(.title2.weight(.bold))
                    Text("UP: \(videoItem.authorName)")
                        .font(.headline)
                    Text("\(videoItem.viewCount.formatted(.number.notation(.compactName))) 次观看 · 时长 \(formattedDuration(videoItem.duration))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    ContentView()
}
