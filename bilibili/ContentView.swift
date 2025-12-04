import SwiftUI
import AVKit
import SDWebImageSwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: RecommendationViewModel
    @StateObject private var followViewModel = FollowFeedViewModel()
    @StateObject private var hotViewModel = HotFeedViewModel()
    @StateObject private var rankingViewModel = RankingViewModel()
    @StateObject private var historyViewModel = HistoryViewModel() // 历史记录 VM
    @StateObject private var loginViewModel = QRLoginViewModel()
    // 添加对 PlayerModel 的观察，以响应恢复状态
    @Environment(PlayerModel.self) private var playerModel

    @State private var isShowingLogin = false
    @State private var selectedTab: Tab = .recommend
    @State private var recommendPath = NavigationPath() // 推荐页面的导航路径，用于恢复状态
    private let autoLoad: Bool

    @MainActor
    init(viewModel: RecommendationViewModel, autoLoad: Bool = true) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.autoLoad = autoLoad
    }

    var body: some View {
        ZStack {
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
                            UserAvatarImage(url: face, size: 22)
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
            
            // 全局播放器层 (ZStack 顶层覆盖)
            // 仅在非沉浸模式且需要显示播放器时显示
            if playerModel.isWindowPlayerPresented && !playerModel.isImmersiveMode {
                if let info = playerModel.playInfo, let item = playerModel.currentVideoItem {
                    PlayerWindowView(playInfo: info, cid: item.cid, bvid: item.id)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(100) // 确保在最顶层
                }
            }
        }
        .task {
            if autoLoad {
                CookieManager.restore()
                await loginViewModel.restoreFromSavedCookies()
                reload(for: selectedTab)
            }
            
            // 检查是否有需要恢复的导航状态 (从沉浸模式退出)
            if let restoredItem = playerModel.restoringVideoItem {
                print("Restoring navigation to: \(restoredItem.title)")
                selectedTab = .recommend // 暂时只支持恢复到推荐页
                recommendPath.append(restoredItem)
                playerModel.restoringVideoItem = nil
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
        .onChange(of: selectedTab) { oldValue, newValue in
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
        // 监听沉浸模式状态，确保退出时关闭播放器层
        .onChange(of: playerModel.isImmersiveMode) { _, isImmersive in
            if isImmersive {
                print("🎬 ContentView: 沉浸模式开启，隐藏 ZStack 播放器层")
                // ZStack 中的 if 条件会自动处理隐藏
            }
        }
        // 监听关闭请求
        .onChange(of: playerModel.shouldDismissPlayerWindow) { _, shouldDismiss in
            guard shouldDismiss else { return }
            print("🎬 ContentView: 收到关闭请求，隐藏 ZStack 播放器层")
            if !playerModel.isImmersiveMode {
                playerModel.cleanup()
            }
            playerModel.isWindowPlayerPresented = false
            playerModel.shouldDismissPlayerWindow = false
        }
    }
    
    @ViewBuilder
    private func tabRootView(for tab: Tab) -> some View {
        if tab == .recommend {
            NavigationStack(path: $recommendPath) {
                mainContent(for: tab)
                    .navigationDestination(for: VideoItem.self) { item in
                        VideoDetailView(videoItem: item)
                            .navigationTitle(item.title)
                    }
            }
        } else {
            NavigationStack {
                mainContent(for: tab)
                    .navigationDestination(for: VideoItem.self) { item in
                        VideoDetailView(videoItem: item)
                            .navigationTitle(item.title)
                    }
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
                            UserAvatarImage(url: profile.face, size: 80, placeholderIcon: "person.crop.circle")
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

// ... rest of existing structs ...
// Note: I will re-include the helper structs (VideoRow, VideoCoverImage, etc.) that were in the original file 
// to ensure the file remains complete and valid.

struct VideoRow: View {
    let videoItem: VideoItem

    var body: some View {
        VideoFeedCard(videoItem: videoItem)
            .padding(.vertical, 6)
    }
}

// 独立的视频封面图片组件
struct VideoCoverImage: View {
    let url: URL?
    let duration: Int
    
    @ViewBuilder
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                WebImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.1)
                        .overlay(Image(systemName: "photo").foregroundColor(.gray))
                }
                .indicator(.activity)
                .frame(width: geometry.size.width, height: geometry.size.width / 1.778)
                .clipped()
                
                Text(formatDuration(duration))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .cornerRadius(4)
                    .padding(6)
                    .foregroundColor(.white)
            }
        }
        .aspectRatio(1.778, contentMode: .fit)
    }
}

struct UserAvatarImage: View {
    let url: URL?
    let size: CGFloat
    let placeholderIcon: String
    
    init(url: URL?, size: CGFloat, placeholderIcon: String = "person.circle") {
        self.url = url
        self.size = size
        self.placeholderIcon = placeholderIcon
    }
    
    @ViewBuilder
    var body: some View {
        WebImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: placeholderIcon)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct HeroCoverImage: View {
    let url: URL?
    let maxWidth: CGFloat
    
    @ViewBuilder
    var body: some View {
        WebImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.gray.opacity(0.1)
                .frame(width: maxWidth, height: maxWidth / 1.778)
                .cornerRadius(20)
        }
        .indicator(.activity)
        .frame(maxWidth: maxWidth)
        .clipped()
        .cornerRadius(20)
    }
}

struct DetailCoverImage: View {
    let url: URL?
    let width: CGFloat
    
    @ViewBuilder
    var body: some View {
        WebImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Color.gray.opacity(0.1)
                .frame(width: width, height: width / 1.778)
                .cornerRadius(24)
        }
        .indicator(.activity)
        .frame(width: width)
        .cornerRadius(24)
        .shadow(radius: 10, y: 5)
    }
}

struct FeedCoverImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    
    @ViewBuilder
    var body: some View {
        WebImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.gray.opacity(0.1)
                .overlay(Image(systemName: "photo").foregroundColor(.gray))
                .frame(width: width, height: height)
                .cornerRadius(12)
        }
        .indicator(.activity)
        .frame(width: width, height: height)
        .clipped()
        .cornerRadius(12)
    }
}

struct VideoGridCard: View {
    let videoItem: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VideoCoverImage(url: videoItem.coverImageURL, duration: videoItem.duration)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(videoItem.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: false)
                
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
                .frame(height: 20)
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.05))
        .cornerRadius(16)
        .hoverEffect()
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
                HeroCoverImage(url: item.coverImageURL, maxWidth: 520)

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title)
                        .font(.extraLargeTitle2.bold())
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
            .padding(24)
            .background(.regularMaterial)
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
            FeedCoverImage(url: videoItem.coverImageURL, width: 160, height: 96)

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
    @State private var isResolving = false
    @State private var playError: String?
    @Environment(PlayerModel.self) private var playerModel
    @StateObject private var relatedViewModel = RelatedViewModel()
    private let playerService = BilibiliPlayerService()
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(videoItem.title)
                                .font(.extraLargeTitle2.bold())
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            HStack(spacing: 16) {
                                Label(videoItem.authorName, systemImage: "person.circle")
                                Label("\(videoItem.viewCount.formatted(.number.notation(.compactName))) 观看", systemImage: "eye")
                                Label(formatDuration(videoItem.duration), systemImage: "clock")
                            }
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 20) {
                            Button {
                                startPlayback(native: false)
                            } label: {
                                Label("播放", systemImage: "play.fill")
                                    .font(.title3.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
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

                    DetailCoverImage(url: videoItem.coverImageURL, width: 500)
                }
                .padding(32)
                .background(.regularMaterial)
                .cornerRadius(32)

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
                .padding(.horizontal, 8)
            }
            .padding(32)
        }
        .overlay {
            if playerModel.isImmersiveMode {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        
        // 添加 onDisappear 清理逻辑
        .onDisappear {
            print("🎬 VideoDetailView onDisappear")
            // 如果不是进入沉浸模式，也不是在显示非沉浸播放器（例如返回上级列表），则应该停止播放
            // 注意：VideoDetailView 的生命周期比较复杂，如果是 NavigationStack push 了新页面，也会 disappear。
            // 所以这里需要判断：是否正在播放且非沉浸模式且非窗口播放模式
            // 但实际上，非沉浸播放器(PlayerWindowView)是覆盖在 ContentView 上的，
            // 如果 VideoDetailView 消失（即用户点击了 NavigationStack 的返回），应该停止播放。
            
            // 简单策略：如果用户从详情页返回列表页，此时 PlayerWindowView 可能还在显示。
            // 应该通知 PlayerWindowView 关闭。
            
            // 我们需要一种方式知道是否是“返回”操作。
            // 可以检查 navigation path，或者简单地，如果当前播放的视频 ID 与此页面的 ID 相同，则停止。
            
            if playerModel.bvid == videoItem.id && !playerModel.isImmersiveMode {
                // 如果正在播放本视频，且不是沉浸模式（沉浸模式会全屏覆盖，详情页还在底部）
                // 这里有一个问题：如果只是进入全屏播放器（PlayerWindowView），它只是 ZStack 的一层，详情页并没有 disappear。
                // 只有当用户点击 Navigation 的返回按钮时，详情页才会 disappear。
                // 此时应该关闭播放器。
                print("🎬 详情页退出，清理播放器")
                playerModel.cleanup()
                playerModel.isWindowPlayerPresented = false
                playerModel.shouldDismissPlayerWindow = true
            }
        }
        
        .task {
            relatedViewModel.fetch(bvid: videoItem.id)
        }
    }

    private func startPlayback(native: Bool) {
        Task {
            print("🚀 [Debug] startPlayback called! Native: \(native)")
            isResolving = true
            playError = nil
            
            playerModel.shouldShowNativePlayer = false
            playerModel.isWindowPlayerPresented = false
            playerModel.playInfo = nil
            playerModel.currentVideoItem = videoItem
            
            do {
                let info = try await playerService.fetchPlayURL(bvid: videoItem.id, cid: videoItem.cid)
                playerModel.playInfo = info
                
                if native {
                     // native logic removed
                } else {
                    print("🎬 设置 isWindowPlayerPresented = true")
                    playerModel.isWindowPlayerPresented = true
                }
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

private func formatDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return String(format: "%d:%02d", minutes, remainingSeconds)
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
            .hoverEffect()
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
