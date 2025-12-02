import Foundation
import Combine
import UIKit // Needed for CGFloat

/// 正在屏幕上显示的弹幕实例
struct ActiveDanmaku: Identifiable, Equatable {
    let id: String
    let item: Danmaku
    var trackIndex: Int // 所在的轨道行号
    let enterTime: Double // 开始显示的时间
    let speed: Double // 移动速度 (pt/s)
    let width: CGFloat // 文字宽度
    
    // 计算当前时刻的 X 坐标 (相对于容器右边缘)
    // xOffset = containerWidth - (timeDiff * speed)
    // 我们记录弹幕尾部的位置用于碰撞检测
    
    static func == (lhs: ActiveDanmaku, rhs: ActiveDanmaku) -> Bool {
        lhs.id == rhs.id
    }
}

class DanmakuEngine: ObservableObject {
    @Published var activeDanmakus: [ActiveDanmaku] = []
    
    private var allDanmakus: [Danmaku] = []
    private var nextIndex: Int = 0 // 下一个待发射的弹幕索引
    
    // 轨道管理：记录每条轨道上最后一条发射的弹幕
    // key: trackIndex, value: ActiveDanmaku
    private var trackLastDanmaku: [Int: ActiveDanmaku] = [:]
    private let trackCount: Int = 12 // 减少轨道数，增加行高，避免上下行文字重叠
    
    // 容器宽度，用于排版计算 (假设一个默认值，View 更新时会传入准确值)
    var containerWidth: CGFloat = 1200 
    
    init() {}
    
    func load(danmakus: [Danmaku]) {
        self.allDanmakus = danmakus.sorted { $0.time < $1.time }
        self.nextIndex = 0
        self.activeDanmakus = []
        self.trackLastDanmaku = [:]
        
        if let first = self.allDanmakus.first {
            print("DanmakuEngine loaded: \(self.allDanmakus.count) items. First: \(first.text)")
        }
    }
    
    /// 更新时间，发射新弹幕
    func update(currentTime: Double) {
        // 1. 清理早已离开屏幕的弹幕
        if Int(currentTime) % 2 == 0 {
            activeDanmakus.removeAll { currentTime - $0.enterTime > 15 }
            // 清理 trackLastDanmaku 中已经消失的引用
            for (track, last) in trackLastDanmaku {
                if currentTime - last.enterTime > 15 {
                    trackLastDanmaku.removeValue(forKey: track)
                }
            }
        }
        
        // 2. 回溯处理 (Seek)
        if nextIndex < allDanmakus.count && allDanmakus[nextIndex].time > currentTime + 5 {
            nextIndex = 0
            activeDanmakus.removeAll()
            trackLastDanmaku.removeAll()
        } else if nextIndex > 0 && allDanmakus[nextIndex - 1].time > currentTime + 1 {
             // Seek backwards
            nextIndex = 0
            activeDanmakus.removeAll()
            trackLastDanmaku.removeAll()
        }
        
        // 找到当前时间点应该播放的弹幕
        // 优化：如果 nextIndex 远落后于 currentTime，快速跳过
        while nextIndex < allDanmakus.count && allDanmakus[nextIndex].time < currentTime - 2.0 {
             nextIndex += 1
        }
        
        // 3. 发射新弹幕
        while nextIndex < allDanmakus.count {
            let danmaku = allDanmakus[nextIndex]
            
            // 还没到时间
            if danmaku.time > currentTime {
                break
            }
            
            fire(danmaku, currentTime: currentTime)
            nextIndex += 1
        }
    }
    
    private func fire(_ item: Danmaku, currentTime: Double) {
        // 估算宽度：大概每个字 24pt + 左右余量
        let estimatedWidth = CGFloat(item.text.count * 24 + 20)
        // 速度：根据文字长度动态调整，字多的飞稍微快一点点，保持阅读体验，或者固定速度
        // 这里采用固定基础速度 + 随机微扰，防止太死板
        let speed: Double = 180.0 + Double.random(in: 0...20)
        
        // 寻找最佳轨道
        let bestTrack = findBestTrack(currentTime: currentTime, speed: speed, width: estimatedWidth)
        
        guard let track = bestTrack else {
            // 如果所有轨道都堵塞，为了性能和观感，丢弃这条弹幕
            // print("Danmaku dropped: \(item.text)")
            return
        }
        
        let active = ActiveDanmaku(
            id: UUID().uuidString,
            item: item,
            trackIndex: track,
            enterTime: currentTime,
            speed: speed,
            width: estimatedWidth
        )
        
        activeDanmakus.append(active)
        trackLastDanmaku[track] = active
    }
    
    private func findBestTrack(currentTime: Double, speed: Double, width: CGFloat) -> Int? {
        // 简单的贪心算法：遍历所有轨道，找到第一条“空闲”的
        // 这里的“空闲”是指：上一条弹幕已经飞出足够远，且我的速度不会追尾上一条
        
        // 随机打乱轨道顺序，防止总是填满上面几行
        let tracks = (0..<trackCount).shuffled()
        
        for i in tracks {
            guard let last = trackLastDanmaku[i] else {
                // 轨道为空，直接用
                return i
            }
            
            // 计算上一条弹幕目前的位置 (相对于屏幕右边缘，正值表示还在屏幕内，越小越靠左)
            // xOffset = ContainerW - (timeDiff * lastSpeed)
            // lastTailX = xOffset + lastWidth
            // 我们希望新弹幕的头部 (ContainerW) 不要碰到 上一条的尾部
            
            let timeDiff = currentTime - last.enterTime
            let lastMovedDistance = timeDiff * last.speed
            // 1. 间距检查：上一条的尾部必须已经飞进屏幕一段距离 (比如 20pt)
            // 即 movedDistance > width + spacing
            if lastMovedDistance < last.width + 50 {
                continue // 还没把屁股挪进屏幕呢，不能发
            }
            
            // 2. 追尾检查 (高级)：如果新弹幕比上一条快，会不会在屏幕内撞上？
            // 只有当新弹幕速度 > 上一条速度时才需要检查
            if speed > last.speed {
                // 相对速度
                let relSpeed = speed - last.speed
                // 初始距离 (上一条尾巴 离 右边缘 的距离)
                let initialGap = lastMovedDistance - last.width
                // 追上所需时间
                let catchUpTime = initialGap / relSpeed
                
                // 屏幕通过时间 (新弹幕飞完屏幕的时间)
                let screenTime = (containerWidth + width) / speed
                
                if catchUpTime < screenTime {
                     continue // 会在屏幕内追尾
                }
            }
            
            return i
        }
        
        return nil
    }
}
