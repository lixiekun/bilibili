import Foundation
import Combine

/// 正在屏幕上显示的弹幕实例
struct ActiveDanmaku: Identifiable, Equatable {
    let id: String
    let item: Danmaku
    var trackIndex: Int // 所在的轨道行号
    let enterTime: Double // 开始显示的时间
    let speed: Double // 移动速度 (pt/s)
    let width: CGFloat // 预估文字宽度，用于计算何时离开屏幕
    
    static func == (lhs: ActiveDanmaku, rhs: ActiveDanmaku) -> Bool {
        lhs.id == rhs.id
    }
}

class DanmakuEngine: ObservableObject {
    @Published var activeDanmakus: [ActiveDanmaku] = []
    
    private var allDanmakus: [Danmaku] = []
    private var nextIndex: Int = 0 // 下一个待发射的弹幕索引
    
    // 轨道管理
    private var trackLastFireTime: [Double] = []
    private let trackCount: Int = 15 
    
    init() {
        trackLastFireTime = Array(repeating: 0, count: trackCount)
    }
    
    func load(danmakus: [Danmaku]) {
        self.allDanmakus = danmakus.sorted { $0.time < $1.time }
        self.nextIndex = 0
        self.activeDanmakus = []
        self.trackLastFireTime = Array(repeating: 0, count: trackCount)
        
        if let first = self.allDanmakus.first {
            print("DanmakuEngine loaded: \(self.allDanmakus.count) items. First item time: \(first.time), text: \(first.text)")
        }
    }
    
    /// 更新时间，发射新弹幕
    func update(currentTime: Double) {
        // 1. 清理早已离开屏幕的弹幕 (假设最慢 10 秒飞完)
        if Int(currentTime) % 2 == 0 {
            activeDanmakus.removeAll { currentTime - $0.enterTime > 12 }
        }
        
        // 2. 回溯处理
        if nextIndex < allDanmakus.count && allDanmakus[nextIndex].time > currentTime + 5 {
            nextIndex = 0
            activeDanmakus.removeAll() // 清空屏幕，防止回溯时弹幕乱飞
        }
        
        // 3. 发射新弹幕
        while nextIndex < allDanmakus.count {
            let danmaku = allDanmakus[nextIndex]
            
            if danmaku.time < currentTime - 1.0 {
                nextIndex += 1
                continue
            }
            
            if danmaku.time > currentTime + 0.2 {
                break
            }
            
            fire(danmaku, currentTime: currentTime)
            nextIndex += 1
        }
        
        #if DEBUG
        if Int(currentTime * 10) % 50 == 0 && !activeDanmakus.isEmpty {
             print("DanmakuEngine: Time \(currentTime), Active count: \(activeDanmakus.count)")
        }
        #endif
    }
    
    private func fire(_ item: Danmaku, currentTime: Double) {
        var bestTrack = -1
        
        // 简单轨道分配
        for i in 0..<trackCount {
            if currentTime - trackLastFireTime[i] > 1.0 { 
                bestTrack = i
                break
            }
        }
        
        if bestTrack == -1 {
            bestTrack = Int.random(in: 0..<trackCount)
        }
        
        trackLastFireTime[bestTrack] = currentTime
        
        // 估算宽度：大概每个字 25pt
        let estimatedWidth = CGFloat(item.text.count * 25)
        // 速度：屏幕宽度(假设1200) + 文字宽度，需要在 8 秒内跑完
        // v = (ContainerW + TextW) / Duration
        // 这里 ContainerW 未知，取个经验值 200 pt/s
        let speed: Double = 200.0 + Double.random(in: 0...50)
        
        let active = ActiveDanmaku(
            id: UUID().uuidString,
            item: item,
            trackIndex: bestTrack,
            enterTime: currentTime,
            speed: speed,
            width: estimatedWidth
        )
        
        activeDanmakus.append(active)
    }
}

