//
//  ContentView.swift
//  bilibili
//
//  Created by 李谢坤 on 2025/5/27.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: RecommendationViewModel
    private let autoLoad: Bool

    @MainActor
    init(viewModel: RecommendationViewModel, autoLoad: Bool = true) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.autoLoad = autoLoad
    }

    var body: some View {
        NavigationStack {
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
                    ScrollView {
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(viewModel.videoItems) { item in
                                NavigationLink(value: item) {
                                    VideoGridCard(videoItem: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                    }
                    .navigationTitle("首页推荐")
                    .toolbar {
                        Button("刷新") {
                            viewModel.fetchRecommendations()
                        }
                    }
                }
            }
            .navigationDestination(for: VideoItem.self) { item in
                VideoDetailView(videoItem: item)
                    .navigationTitle(item.title)
            }
        }
        .task {
            if autoLoad {
                viewModel.fetchRecommendations()
            }
        }
    }
}

struct VideoRow: View {
    let videoItem: VideoItem

    var body: some View {
        VideoFeedCard(videoItem: videoItem)
            .padding(.vertical, 6)
    }
}

struct VideoGridCard: View {
    let videoItem: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: videoItem.coverImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(height: 150)
                            .clipped()
                            .cornerRadius(14)
                    case .failure:
                        Image(systemName: "photo")
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(14)
                    case .empty:
                        ProgressView()
                            .frame(height: 150)
                    @unknown default:
                        EmptyView()
                    }
                }

                Text(formatDuration(videoItem.duration))
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundColor(.white)
                    .padding(10)
            }

            Text(videoItem.title)
                .font(.headline)
                .lineLimit(2)
            Text("UP: \(videoItem.authorName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(videoItem.viewCount.formatted(.number.notation(.compactName))) 次观看")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06))
        )
    }
}

struct VideoFeedCard: View {
    let videoItem: VideoItem

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            AsyncImage(url: videoItem.coverImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 96)
                        .clipped()
                        .cornerRadius(12)
                case .failure:
                    Image(systemName: "photo")
                        .frame(width: 160, height: 96)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                case .empty:
                    ProgressView()
                        .frame(width: 160, height: 96)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(videoItem.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("UP: \(videoItem.authorName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(videoItem.viewCount.formatted(.number.notation(.compactName))) 次观看 · \(formatDuration(videoItem.duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06))
        )
    }
}

struct VideoDetailView: View {
    let videoItem: VideoItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(videoItem.title)
                            .font(.title.weight(.bold))
                            .lineLimit(2)

                        HStack(spacing: 16) {
                            Label(videoItem.authorName, systemImage: "person.circle")
                            Label(videoItem.viewCount.formatted(.number.notation(.compactName)) + " 次观看", systemImage: "eye")
                            Label(formatDuration(videoItem.duration), systemImage: "clock")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            DetailActionButton(title: "播放", systemImage: "play.fill")
                            DetailActionButton(title: "点赞", systemImage: "hand.thumbsup")
                            DetailActionButton(title: "收藏", systemImage: "star")
                            DetailActionButton(title: "不喜欢", systemImage: "hand.thumbsdown")
                        }
                    }

                    AsyncImage(url: videoItem.coverImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(width: 280, height: 158)
                                .clipped()
                                .cornerRadius(18)
                        case .failure:
                            Image(systemName: "photo")
                                .frame(width: 280, height: 158)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(18)
                        case .empty:
                            ProgressView()
                                .frame(width: 280, height: 158)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                Text("简介")
                    .font(.headline)
                Text("这里展示视频简介、标签和更多信息。")
                    .foregroundStyle(.secondary)

                Text("相关推荐")
                    .font(.headline)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModelRecommendationsMock(), id: \.id) { mock in
                        VideoGridCard(videoItem: mock)
                    }
                }
            }
            .padding()
        }
    }
}

private func formatDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

private func viewModelRecommendationsMock() -> [VideoItem] {
    [
        .mock(id: "BV1xx411c7mD", title: "【合集】2233 经典曲目", author: "哔哩哔哩娘", views: 1200000, duration: 320),
        .mock(id: "BV1jj411k7Tp", title: "天马行空的创意短片", author: "创作星球", views: 840000, duration: 210),
        .mock(id: "BV1zz4y1A7QD", title: "编程菜鸟的 SwiftUI 之旅", author: "学习笔记本", views: 39214, duration: 445),
        .mock(id: "BV1aa411c7mE", title: "音乐现场：燃炸一夏", author: "音乐频道", views: 502000, duration: 188)
    ]
}

private struct DetailActionButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        Button {
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.footnote)
            }
            .frame(width: 90, height: 70)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView(viewModel: .preview, autoLoad: false)
}
