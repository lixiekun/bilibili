import SwiftUI
import AVKit

struct DanmakuView: View {
    @ObservedObject var engine: DanmakuEngine
    let player: AVPlayer?
    
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timelineContext in
                let currentTime = player?.currentTime().seconds ?? 0
                let containerWidth = proxy.size.width
                
                // 使用 Canvas 进行高性能绘制，避免 View 布局系统的干扰
                Canvas { context, size in
                    for active in engine.activeDanmakus {
                        // 计算位置，确保 timeDiff 不会出现负数造成瞬间跳动
                        let timeDiff = max(0, currentTime - active.enterTime)
                        let xOffset = containerWidth - CGFloat(timeDiff * active.speed)
                        
                        let leftBound = -CGFloat(active.width) - 80
                        let rightBound = containerWidth + CGFloat(active.width) + 80
                        
                        if xOffset > leftBound && xOffset < rightBound {
                            // 准备文字
                            let text = Text(active.item.text)
                                .font(.system(size: CGFloat(active.item.fontSize)))
                                .foregroundColor(active.item.color)
                            
                            // 解决文字阴影问题：Canvas 的 context.draw 阴影处理方式不同
                            // 这里我们通过绘制两次来实现简单的阴影效果，性能开销很小
                            
                            // 1. 绘制阴影
                            let shadowText = Text(active.item.text)
                                .font(.system(size: CGFloat(active.item.fontSize)))
                                .foregroundColor(.black.opacity(0.8))
                            
                            // 修复弹幕下坠问题：确保 yPosition 是 float 类型，并且轨道高度固定
                            let yPosition = Double(active.trackIndex * 32 + 25)
                            let point = CGPoint(x: xOffset, y: yPosition)
                            let shadowPoint = CGPoint(x: xOffset + 1, y: yPosition + 1)
                            
                            // 解析 Text 为 GraphicsContext.ResolvedText
                            let resolvedShadow = context.resolve(shadowText)
                            context.draw(resolvedShadow, at: shadowPoint, anchor: .leading)
                            
                            // 2. 绘制主体
                            let resolvedText = context.resolve(text)
                            context.draw(resolvedText, at: point, anchor: .leading)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false) // 确保完全不响应交互
        .accessibilityHidden(true) // 隐藏辅助功能，防止 VoiceOver 聚焦弹幕
    }
}
