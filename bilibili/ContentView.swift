//
//  ContentView.swift
//  bilibili
//
//  Created by 李谢坤 on 2025/5/27.
//

import SwiftUI
import AVKit

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: RecommendationViewModel
    @StateObject private var followViewModel = FollowFeedViewModel()
    @StateObject private var hotViewModel = HotFeedViewModel()
    @StateObject private var rankingViewModel = RankingViewModel()
    @StateObject private var loginViewModel = QRLoginViewModel()
    @State private var isShowingLogin = false
    @State private var selectedTab: Tab = .recommend
    private let autoLoad: Bool

    @MainActor
    init(viewModel: RecommendationViewModel, autoLoad: Bool = true) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.autoLoad = autoLoad
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                mainContent
                    .tag(Tab.recommend)
                    .tabItem { Label("推荐", systemImage: "house.fill") }
                mainContent
                    .tag(Tab.follow)
                    .tabItem { Label("关注", systemImage: "person.2.fill") }
                mainContent
                    .tag(Tab.hot)
                    .tabItem { Label("热门", systemImage: "flame.fill") }
                mainContent
                    .tag(Tab.ranking)
                    .tabItem { Label("排行榜", systemImage: "list.number") }
                mainContent
                    .tag(Tab.profile)
                    .tabItem {
                        if let face = loginViewModel.userProfile?.face {
                            AsyncImage(url: face) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                default:
                                    Image(systemName: "person.circle")
                                }
                            }
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                        } else {
                            Label("我的", systemImage: "person.circle")
                        }
                    }
            }
            .navigationDestination(for: VideoItem.self) { item in
                VideoDetailView(videoItem: item)
                    .navigationTitle(item.title)
            }
            .sheet(isPresented: $isShowingLogin, onDismiss: {
                loginViewModel.cancel()
            }) {
                QRLoginView(viewModel: loginViewModel)
                    .presentationDetents([.fraction(0.5), .medium, .large])
            }
        }
        .task {
            if autoLoad {
                CookieManager.restore()
                await loginViewModel.restoreFromSavedCookies()
                reload()
            }
        }
        .onReceive(loginViewModel.$state) { state in
            if case .confirmed = state {
                isShowingLogin = false
                reload()
            }
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == .follow,
               loginViewModel.userProfile != nil,
               followViewModel.videoItems.isEmpty {
                followViewModel.refresh()
            } else if newValue == .hot, hotViewModel.videoItems.isEmpty {
                hotViewModel.fetch()
            } else if newValue == .ranking, rankingViewModel.videoItems.isEmpty {
                rankingViewModel.fetch()
            }
        }
    }

    private var activeViewModel: any FeedProviding {
        switch selectedTab {
        case .recommend:
            return viewModel
        case .follow:
            return followViewModel
        case .hot:
            return hotViewModel
        case .ranking:
            return rankingViewModel
        case .profile:
            return viewModel
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tabTitle)
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(activeViewModel.isLoading)
            }

            if activeViewModel.isLoading && activeViewModel.videoItems.isEmpty {
                ProgressView("正在加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = activeViewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("错误: \(errorMessage)")
                        .foregroundColor(.red)
                    Button("重试") { reload() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if activeViewModel.videoItems.isEmpty {
                Text("暂无内容")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                contentView
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .recommend:
            ScrollView {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.videoItems) { item in
                        NavigationLink(value: item) {
                            VideoGridCard(videoItem: item)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if item == viewModel.videoItems.last && viewModel.canLoadMore {
                                viewModel.fetchRecommendations()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)

                if viewModel.isLoading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else if !viewModel.canLoadMore {
                    Text("没有更多了")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        case .follow:
            ScrollView {
                if let msg = followViewModel.errorMessage {
                    Text(msg)
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                }

                let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(followViewModel.videoItems) { item in
                        NavigationLink(value: item) {
                            VideoGridCard(videoItem: item)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if item == followViewModel.videoItems.last {
                                followViewModel.fetch()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        case .hot:
            ScrollView {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(hotViewModel.videoItems) { item in
                        NavigationLink(value: item) {
                            VideoGridCard(videoItem: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)

                if hotViewModel.isLoading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        case .ranking:
            ScrollView {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(rankingViewModel.videoItems) { item in
                        NavigationLink(value: item) {
                            VideoGridCard(videoItem: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)

                if rankingViewModel.isLoading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        case .profile:
            VStack(spacing: 16) {
                if let profile = loginViewModel.userProfile {
                    AsyncImage(url: profile.face) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    Text(profile.uname).font(.title2.bold())
                    Button("退出登录") {
                        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
                        CookieManager.clear()
                        loginViewModel.userProfile = nil
                        followViewModel.videoItems = []
                        followViewModel.errorMessage = nil
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("未登录")
                    Button("扫码登录") {
                        isShowingLogin = true
                        loginViewModel.startLogin()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private func reload() {
        switch selectedTab {
        case .recommend:
            viewModel.refresh()
        case .follow:
            followViewModel.refresh()
        case .hot:
            hotViewModel.fetch()
        case .ranking:
            rankingViewModel.fetch()
        case .profile:
            break
        }
    }

    private enum Tab {
        case recommend
        case follow
        case hot
        case ranking
        case profile
    }

    private var tabTitle: String {
        switch selectedTab {
        case .recommend: return "首页推荐"
        case .follow: return "关注动态"
        case .hot: return "热门"
        case .ranking: return "排行榜"
        case .profile: return "我的"
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

struct RecommendHomeView: View {
    let items: [VideoItem]

    private var hero: VideoItem? { items.first }
    private var sections: [(title: String, videos: [VideoItem])] {
        let chunkSize = 8
        let chunks = Array(items.dropFirst()).chunked(into: chunkSize)
        let titles = ["热门推荐", "动画精选", "科技科普", "音乐·舞蹈", "游戏实况", "生活Vlog"]
        return chunks.enumerated().map { idx, chunk in
            (titles[idx % titles.count], Array(chunk))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let hero {
                    HeroView(item: hero)
                }

                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    SectionHeader(title: section.title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 18) {
                            ForEach(section.videos) { item in
                                NavigationLink(value: item) {
                                    VideoGridCard(videoItem: item)
                                        .frame(width: 320)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.vertical, 24)
        }
    }
}

private struct HeroView: View {
    let item: VideoItem

    var body: some View {
        NavigationLink(value: item) {
            HStack(spacing: 24) {
                AsyncImage(url: item.coverImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: 520, height: 290)
                            .clipped()
                            .cornerRadius(20)
                    case .failure:
                        Image(systemName: "photo")
                            .frame(width: 520, height: 290)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(20)
                    case .empty:
                        ProgressView()
                            .frame(width: 520, height: 290)
                    @unknown default:
                        EmptyView()
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title)
                        .font(.title.weight(.bold))
                        .lineLimit(2)
                    Text("UP: \(item.authorName)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("\(item.viewCount.formatted(.number.notation(.compactName))) 次观看 · \(formatDuration(item.duration))")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        DetailActionButton(title: "播放", systemImage: "play.fill")
                        DetailActionButton(title: "收藏", systemImage: "star")
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 24)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
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
    @State private var playerURL: URL?
    @State private var isResolving = false
    @State private var playError: String?
    private let playerService = BilibiliPlayerService()

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
                            Button {
                                startPlayback()
                            } label: {
                                DetailActionButtonContent(title: "播放", systemImage: "play.fill")
                            }
                            .buttonStyle(.plain)
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

                if let playError {
                    Text(playError)
                        .foregroundColor(.red)
                } else if isResolving {
                    ProgressView("正在解析播放地址…")
                }

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
        .fullScreenCover(item: $playerURL) { url in
            PlayerWindowView(url: url)
                .ignoresSafeArea()
        }
    }

    private func startPlayback() {
        Task {
            isResolving = true
            playError = nil
            do {
                let info = try await playerService.fetchPlayURL(bvid: videoItem.id, cid: videoItem.cid)
                playerURL = info.url
            } catch {
                #if DEBUG
                print("playback failed for \(videoItem.id): \(error)")
                #endif
                if case BilibiliPlayerService.PlayerError.apiError(let code, let message) = error {
                    playError = "无法播放：\(message) (code \(code))"
                } else if case BilibiliPlayerService.PlayerError.missingCID = error {
                    playError = "无法播放：缺少 CID"
                } else if case BilibiliPlayerService.PlayerError.noPlayableURL = error {
                    playError = "无法播放：未返回可用链接"
                } else {
                    playError = "无法播放：\(error.localizedDescription)"
                }
            }
            isResolving = false
        }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
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
            DetailActionButtonContent(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

struct DetailActionButtonContent: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.footnote)
        }
        .frame(width: 90, height: 70)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct QRLoginView: View {
    @ObservedObject var viewModel: QRLoginViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("扫码登录 Bilibili")
                .font(.title2.weight(.semibold))

            Group {
                switch viewModel.state {
                case .idle, .generating:
                    ProgressView("正在生成二维码…")
                        .frame(height: 240)
                case .scanning(let url, _):
                    VStack(spacing: 12) {
                        if let qr = viewModel.qrImage {
                            qr
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 240, height: 240)
                                .cornerRadius(12)
                        } else {
                            ProgressView()
                                .frame(width: 240, height: 240)
                        }
                        Text(url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                case .confirmed:
                    Label("登录成功", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3.weight(.semibold))
                case .expired:
                    Label("二维码已失效，请刷新", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3.weight(.semibold))
                case .failed(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.body)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 16) {
                Button("刷新二维码") {
                    viewModel.startLogin()
                }
                .buttonStyle(.borderedProminent)

                Button("取消") {
                    viewModel.cancel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: 420)
        .onAppear {
            if case .idle = viewModel.state {
                viewModel.startLogin()
            }
        }
    }
}

#Preview {
    ContentView(viewModel: RecommendationViewModel(), autoLoad: false)
}
