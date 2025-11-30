import Foundation
import SwiftUI

/// 弹幕模式
enum DanmakuMode: Int {
    case scrollR2L = 1 // 滚动弹幕（右到左）
    case scrollL2R = 6 // 滚动弹幕（左到右）
    case top = 5       // 顶部弹幕
    case bottom = 4    // 底部弹幕
    case unknown = 0
}

/// 单条弹幕数据模型
struct Danmaku: Identifiable, Equatable {
    let id: String = UUID().uuidString
    let text: String
    let time: Double     // 出现时间（秒）
    let mode: DanmakuMode
    let fontSize: Int
    let color: Color
    let timestamp: TimeInterval // 发送时间戳
    
    // 原始属性字符串，用于解析
    // 格式: time,mode,fontSize,color,timestamp,pool,userHash,rowId
    // 例: "55.28500,1,25,16777215,1683521122,0,a1b2c3d4,1234567890"
    init?(attributes: String, content: String) {
        let parts = attributes.split(separator: ",")
        guard parts.count >= 4 else { return nil }
        
        self.text = content
        self.time = Double(parts[0]) ?? 0
        
        let modeInt = Int(parts[1]) ?? 1
        // B站 XML 中：1, 2, 3 都是滚动弹幕
        if [1, 2, 3].contains(modeInt) {
            self.mode = .scrollR2L
        } else if modeInt == 5 {
            self.mode = .top
        } else if modeInt == 4 {
            self.mode = .bottom
        } else {
            self.mode = .unknown
        }
        
        self.fontSize = Int(parts[2]) ?? 25
        
        let colorInt = Int(parts[3]) ?? 16777215 // 默认白色
        self.color = Color(rgb: colorInt)
        
        self.timestamp = TimeInterval(parts[4]) ?? 0
    }
}

extension Color {
    init(rgb: Int) {
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

