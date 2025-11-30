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
    @StateObject private var historyViewModel = HistoryViewModel() // 历史记录 VM
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
        TabView(selection: $selectedTab) {
            tabRootView(for: .recommend)
                .tag(Tab.recommend)
                .tabItem { Label("推荐", systemImage: "house.fill") }

            tabRootView(for: .follow)
                .tag(Tab.follow)
                .tabItem { Label("关注", systemImage: "person.2.fill") }

            tabRootView(for: .hot)
                .tag(Tab.hot)
                .tabItem { Label("热门", systemImage: "flame.fill") }

            tabRootView(for: .ranking)
                .tag(Tab.ranking)
                .tabItem { Label("排行榜", systemImage: "list.number") }

            tabRootView(for: .profile)
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
        .sheet(isPresented: $isShowingLogin, onDismiss: {
            loginViewModel.cancel()
        }) {
            QRLoginView(viewModel: loginViewModel)
                .presentationDetents([.fraction(0.5), .medium, .large])
        }
        .task {
            if autoLoad {
                CookieManager.restore()
                await loginViewModel.restoreFromSavedCookies()
                reload(for: selectedTab)
            }
            
            // 预热 WBI 签名 Key，避免首次播放卡顿
            Task.detached {
                var signer = BilibiliWBI()
                try? await signer.ensureKey()
            }
        }
        .onReceive(loginViewModel.$state) { state in
            if case .confirmed = state {
                isShowingLogin = false
                reload(for: selectedTab)
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
    
    @ViewBuilder
    private func tabRootView(for tab: Tab) -> some View {
        NavigationStack {
            mainContent(for: tab)
                .navigationDestination(for: VideoItem.self) { item in
                    VideoDetailView(videoItem: item)
                        .navigationTitle(item.title)
                }
        }
    }

    private func viewModel(for tab: Tab) -> any FeedProviding {
        switch tab {
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
    private func mainContent(for tab: Tab) -> some View {
        let activeViewModel = viewModel(for: tab)
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title(for: tab))
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    reload(for: tab)
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
                    Button("重试") { reload(for: tab) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if activeViewModel.videoItems.isEmpty {
                Text("暂无内容")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                contentView(for: tab)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func contentView(for tab: Tab) -> some View {
        switch tab {
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
                            // 预加载：当显示到倒数第4个视频时，就开始加载下一页
                            let thresholdIndex = viewModel.videoItems.index(viewModel.videoItems.endIndex, offsetBy: -4, limitedBy: 0) ?? 0
                            if let currentIndex = viewModel.videoItems.firstIndex(where: { $0.id == item.id }),
                               currentIndex >= thresholdIndex,
                               viewModel.canLoadMore {
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
            .refreshable { reload(for: tab) }
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

                if followViewModel.isLoading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .refreshable { reload(for: tab) }
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
            .refreshable { reload(for: tab) }
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
            .refreshable { reload(for: tab) }
        case .profile:
            ScrollView {
                VStack(spacing: 24) {
                    if let profile = loginViewModel.userProfile {
                        // 用户信息头
                        VStack(spacing: 16) {
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
                                historyViewModel.items = [] // 清空历史
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.bottom, 24)
                        
                        // 历史记录列表
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("历史记录")
                                    .font(.title2.bold())
                                Spacer()
                                Button {
                                    historyViewModel.fetch()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                            
                            if historyViewModel.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else if let error = historyViewModel.errorMessage {
                                Text(error)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 24)
                            } else if historyViewModel.items.isEmpty {
                                Text("暂无历史记录")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 24)
                            } else {
                                let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(historyViewModel.items) { item in
                                        NavigationLink(value: item) {
                                            VideoGridCard(videoItem: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    } else {
                        VStack(spacing: 20) {
                            Text("未登录")
                                .font(.title)
                            Button("扫码登录") {
                                isShowingLogin = true
                                loginViewModel.startLogin()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    }
                }
                .padding(.vertical, 24)
            }
            .refreshable {
                if loginViewModel.userProfile != nil {
                    historyViewModel.fetch()
                }
            }
            .onAppear {
                if loginViewModel.userProfile != nil && historyViewModel.items.isEmpty {
                    historyViewModel.fetch()
                }
            }
        }
    }

    private func reload(for tab: Tab) {
        switch tab {
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

    private func title(for tab: Tab) -> String {
        switch tab {
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
        VStack(alignment: .leading, spacing: 10) {
            // 封面区域
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: videoItem.coverImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1.778, contentMode: .fill) // 16:9 比例
                    case .failure:
                        Color.gray.opacity(0.1)
                            .overlay(Image(systemName: "photo").foregroundColor(.gray))
                            .aspectRatio(1.778, contentMode: .fit)
                    case .empty:
                        Color.gray.opacity(0.1)
                            .aspectRatio(1.778, contentMode: .fit)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped() // 确保内容不会溢出圆角
                
                // 时长标签
                Text(formatDuration(videoItem.duration))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial) // 使用磨砂玻璃效果
                    .cornerRadius(4)
                    .padding(6)
                    .foregroundColor(.white)
            }
            .cornerRadius(12) // 封面圆角

            // 信息区域
            VStack(alignment: .leading, spacing: 4) {
                Text(videoItem.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .topLeading) // 固定两行标题的高度 (大约值，视字体大小调整)
                    .fixedSize(horizontal: false, vertical: true) // 允许垂直方向根据内容调整，但受限于 frame
                
                HStack {
                    Image(systemName: "play.circle")
                        .font(.caption)
                    Text(videoItem.viewCount.formatted(.number.notation(.compactName)))
                        .font(.caption)
                    
                    Spacer()
                    
                    Text(videoItem.authorName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .background(Color.primary.opacity(0.05)) // 极其轻微的背景
        .cornerRadius(16)
        // 移除 strokeBorder，visionOS 中通常使用 hover effect 和 depth
        .hoverEffect() // 添加 visionOS 标准悬停效果
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
                            .aspectRatio(1.778, contentMode: .fill) // 16:9
                            .frame(maxWidth: 520) // 限制最大宽度，高度自动
                            .clipped()
                            .cornerRadius(20)
                    case .failure:
                        Color.gray.opacity(0.1)
                            .frame(width: 520, height: 292) // 保持大约 16:9
                            .cornerRadius(20)
                    case .empty:
                        ProgressView()
                            .frame(width: 520, height: 292)
                    @unknown default:
                        EmptyView()
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title)
                        .font(.extraLargeTitle2.bold()) // visionOS 上可以使用更大的字体
                        .lineLimit(2)
                    
                    HStack {
                         Label(item.authorName, systemImage: "person.circle")
                         Label("\(item.viewCount.formatted(.number.notation(.compactName))) 观看", systemImage: "eye")
                    }
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    
                    Text(formatDuration(item.duration))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        
                    Spacer()
                    
                    HStack(spacing: 12) {
                        DetailActionButton(title: "播放", systemImage: "play.fill")
                        DetailActionButton(title: "收藏", systemImage: "star")
                    }
                }
                .padding(.vertical, 8)
                Spacer()
            }
            .padding(24) // 增加内边距
            .background(.regularMaterial) // 给整个 Hero 卡片加个背景
            .cornerRadius(32)
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
    @StateObject private var relatedViewModel = RelatedViewModel()
    private let playerService = BilibiliPlayerService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // 顶部 Hero 区域：左侧信息 + 右侧封面
                HStack(alignment: .top, spacing: 32) {
                    // 左侧：视频信息与操作
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(videoItem.title)
                                .font(.extraLargeTitle2.bold())
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true) // 允许标题换行并自适应高度
                            
                            HStack(spacing: 16) {
                                Label(videoItem.authorName, systemImage: "person.circle")
                                Label("\(videoItem.viewCount.formatted(.number.notation(.compactName))) 观看", systemImage: "eye")
                                Label(formatDuration(videoItem.duration), systemImage: "clock")
                            }
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        }

                        // 操作按钮组
                        HStack(spacing: 20) {
                            Button {
                                startPlayback()
                            } label: {
                                Label("播放", systemImage: "play.fill")
                                    .font(.title3.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
                            // 辅助操作按钮
                            HStack(spacing: 12) {
                                DetailActionButton(title: "点赞", systemImage: "hand.thumbsup")
                                DetailActionButton(title: "收藏", systemImage: "star")
                                DetailActionButton(title: "分享", systemImage: "square.and.arrow.up")
                            }
                        }
                        
                        if let playError {
                            Text(playError)
                                .foregroundColor(.red)
                                .font(.callout)
                                .padding(12)
                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        } else if isResolving {
                            HStack {
                                ProgressView()
                                .padding(.trailing, 8)
                                Text("正在解析播放地址…")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("简介")
                                .font(.title3.bold())
                            Text("这里展示视频简介、标签和更多信息。")
                                .foregroundStyle(.secondary)
                                .font(.body)
                                .lineLimit(4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 右侧：大封面图
                    AsyncImage(url: videoItem.coverImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(1.778, contentMode: .fit) // 16:9
                                .frame(width: 500) // 固定封面宽度
                                .cornerRadius(24)
                                .shadow(radius: 10, y: 5) // 添加阴影增加层次感
                        case .failure:
                            Color.gray.opacity(0.1)
                                .frame(width: 500, height: 281)
                                .cornerRadius(24)
                        case .empty:
                            ProgressView()
                                .frame(width: 500, height: 281)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .padding(32) // 增加顶部区域的内边距
                .background(.regularMaterial) // 毛玻璃背景
                .cornerRadius(32)

                // 底部：相关推荐
                VStack(alignment: .leading, spacing: 20) {
                    Text("相关推荐")
                        .font(.title2.bold())
                        .padding(.horizontal, 8)

                    let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(Array(relatedViewModel.items.prefix(8))) { item in
                            NavigationLink(value: item) {
                                VideoGridCard(videoItem: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if relatedViewModel.isLoading {
                        ProgressView("加载相关推荐…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if let msg = relatedViewModel.errorMessage {
                        Text(msg)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8) // 与上方对齐
            }
            .padding(32) // 整个页面的外边距
        }
        .navigationBarTitleDisplayMode(.inline) // 详情页标题栏精简
        .fullScreenCover(item: $playerURL) { url in
            PlayerWindowView(url: url, cid: videoItem.cid, bvid: videoItem.id)
                .ignoresSafeArea()
        }
        .task {
            relatedViewModel.fetch(bvid: videoItem.id)
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
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .hoverEffect() // 添加悬停效果
            .clipShape(Capsule())
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
