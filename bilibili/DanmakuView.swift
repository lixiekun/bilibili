import SwiftUI
import AVKit

struct DanmakuView: View {
    @ObservedObject var engine: DanmakuEngine
    let player: AVPlayer?
    
    var body: some View {
        GeometryReader { proxy in
            // 使用 TimelineView 驱动每一帧的渲染
            TimelineView(.animation) { context in
                let currentTime = player?.currentTime().seconds ?? 0
                let containerWidth = proxy.size.width
                
                ZStack {
                    ForEach(engine.activeDanmakus) { active in
                        // 计算位置
                        // x = containerWidth - (videoTime - enterTime) * speed
                        let timeDiff = currentTime - active.enterTime
                        let xOffset = containerWidth - CGFloat(timeDiff * active.speed)
                        
                        // 简单的性能优化：如果已经跑出屏幕左边，就不渲染 Text (虽然 ForEach 还在)
                        // 实际上 Engine 会定期清理，所以这里只需要渲染
                        // 增加 NaN/Inf 检查，防止 crash
                        if xOffset.isFinite,
                           xOffset > -active.width - 100,
                           xOffset < containerWidth + 100 {
                            Text(active.item.text)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(active.item.color)
                                .shadow(color: .black.opacity(0.8), radius: 1, x: 1, y: 1)
                                .fixedSize() // 确保文字不换行
                                .position(x: 0, y: 0) // Reset position context
                                .offset(x: xOffset, y: CGFloat(active.trackIndex * 32 + 20))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// 移除旧的 DanmakuCell，因为逻辑已经移入 DanmakuView 主体以利用 TimelineView


