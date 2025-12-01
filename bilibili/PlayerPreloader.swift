//
//  PlayerPreloader.swift
//  bilibili
//
//  Created for preloading player components
//

import AVKit
import SwiftUI

/// 播放器预加载管理器，用于在应用启动时预加载播放器组件，提升首次播放速度
@MainActor
class PlayerPreloader: ObservableObject {
    static let shared = PlayerPreloader()
    
    private var preloadedPlayer: AVPlayer?
    private var preloadedViewController: AVPlayerViewController?
    private var preloadedDanmakuEngine: DanmakuEngine?
    
    private init() {
        // 私有初始化，确保单例
    }
    
    /// 预加载播放器组件
    func preload() {
        Task {
            // 创建一个空的播放器用于预热 AVPlayer 框架
            let emptyAsset = AVURLAsset(url: URL(string: "about:blank")!)
            let emptyItem = AVPlayerItem(asset: emptyAsset)
            let player = AVPlayer(playerItem: emptyItem)
            
            // 预创建 AVPlayerViewController，触发其初始化
            let vc = AVPlayerViewController()
            vc.player = player
            vc.showsPlaybackControls = true
            
            // 预加载一些常用的配置，触发内部初始化
            player.automaticallyWaitsToMinimizeStalling = true
            emptyItem.preferredPeakBitRate = 0
            
            // 预创建 DanmakuEngine
            let engine = DanmakuEngine()
            
            // 保存预加载的组件（保持引用，避免被释放）
            self.preloadedPlayer = player
            self.preloadedViewController = vc
            self.preloadedDanmakuEngine = engine
            
            // 触发一些内部初始化
            _ = player.currentItem
            _ = vc.contentOverlayView
            
            // 短暂延迟后清理，释放资源但保留初始化效果
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 秒
            cleanup()
        }
    }
    
    /// 获取预加载的 DanmakuEngine（如果存在）
    func getPreloadedDanmakuEngine() -> DanmakuEngine? {
        return preloadedDanmakuEngine
    }
    
    /// 清理预加载的资源
    func cleanup() {
        preloadedPlayer?.pause()
        preloadedPlayer?.replaceCurrentItem(with: nil)
        preloadedPlayer = nil
        preloadedViewController = nil
        preloadedDanmakuEngine = nil
    }
}

