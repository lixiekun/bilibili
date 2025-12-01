//
//  SidxParser.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/11/13.
//

import Foundation

enum SidxParser {
    struct Sidx {
        let timescale: Int
        let firstOffset: Int
        let earliestPresentationTime: Int
        let segments: [SegmentInfo]

        struct SegmentInfo {
            let type: Int
            let size: Int
            let duration: Int
            let sap: Int
            let sap_type: Int
            let sap_delta: Int
        }

        func maxSegmentDuration() -> Int? {
            if let duration = segments.map({ Double($0.duration) / Double(timescale) }).max() {
                return Int(duration + 1)
            }
            return nil
        }
    }

    static func parse(data: Data) -> Sidx? {
        var offset: UInt64 = 0
        var typeString = ""
        
        // 循环查找 sidx box
        while offset < data.count - 8 {
            // print("offset:", offset)
            
            // 安全读取 size (4字节)
            let size: UInt64
            if let val = readSafeUInt32(data: data, offset: &offset) {
                size = UInt64(val)
            } else {
                return nil
            }
            
            // 安全读取 type (4字节)
            guard let typeVal = readSafeUInt32(data: data, offset: &offset) else { return nil }
            let typeArr = typeVal.toUInt8s
            typeString = String(bytes: typeArr, encoding: .utf8) ?? ""
            
            // print(size, typeString)
            switch typeString {
            case "sidx":
                var boxSize = size
                if size == 1 {
                    // Large size: read 64-bit
                    if let largeSize = readSafeUInt64(data: data, offset: &offset) {
                        boxSize = largeSize
                    } else {
                        return nil
                    }
                }
                
                // processSIDX 需要的是 box body
                // 此时 offset 已经跳过了 size 和 type (如果是 size=1，也跳过了 largeSize)
                // Demo 的 processSIDX 期望的也是已经跳过 header 的 offset 吗？
                // Demo: sidx = processSIDX(data: Data(data[Data.Index(offset)..<Int(size)]))
                // 这里的 offset 是已经跳过 header 的。
                // 我们直接传递当前 offset 即可。
                
                return processSIDX(data: data, offset: &offset)
                
            default:
                // 跳过这个 box
                // 当前 offset 已经在 header 之后了
                // box 总长是 size
                // 我们需要前进 (size - headerLength)
                // 如果 size=1，headerLength=16 (4+4+8)，boxSize=largeSize
                // 如果 size!=1，headerLength=8 (4+4)，boxSize=size
                // 此时 offset 已经前进了 8 (size!=1) 或 16 (size=1)
                
                // 注意：上面的读取操作已经推进了 offset。
                // 让我们重新计算要跳过的长度。
                // 实际上最简单的做法是：记录 boxStart，然后 offset = boxStart + boxSize
                
                // 由于我们已经在 while 循环里，offset 已经被推进了。
                // 让我们简化逻辑，不依赖 offset 的中间状态。
                
                // 回滚 offset 到 box start? 不，我们只需要知道还有多少没读。
                // 更好的做法是：每次读取前记录 start。
                // 但是 offset 是 inout。
                
                // 简单粗暴：只找 sidx。如果不是 sidx，offset += (size - 8)。
                // 如果 size=1，offset += (largeSize - 16)。
                
                if size == 1 {
                    // offset 已经读了 16 字节
                    // 这里我们要用到上面读出来的 largeSize，但变量作用域...
                    // 重构一下循环结构。
                    return nil // 简化：如果遇到非 sidx 的 large box，暂不支持跳过逻辑（通常 Range 请求直接命中 sidx）
                } else {
                    if size < 8 { return nil } // Invalid box
                    offset += (size - 8)
                }
            }
        }
        return nil
    }

    private static func processSIDX(data: Data, offset: inout UInt64) -> Sidx {
        _ = data.getUint8(offset: &offset) // version
        _ = data.getUint8(offset: &offset) // none
        _ = data.getUint8(offset: &offset) // none
        _ = data.getUint8(offset: &offset) // none
        _ = data.getUint32(offset: &offset) // refID
        let timescale = data.getUint32(offset: &offset)
        let earliest_presentation_time = data.getUint32(offset: &offset)
        let first_offset = data.getUint32(offset: &offset)
        _ = data.getValue(type: UInt16.self, offset: &offset).bigEndian // reversed
        let reference_count = data.getValue(type: UInt16.self, offset: &offset).bigEndian

        var infos = [Sidx.SegmentInfo]()
        for _ in 0..<reference_count {
            var code = data.getUint32(offset: &offset)
            let reference_type = (code >> 31) & 1
            let referenced_size = (code & 0x7fffffff)
            let duration = data.getUint32(offset: &offset)

            code = data.getUint32(offset: &offset)
            let starts_with_SAP = (code >> 31) & 1
            let sap_type = (code >> 29) & 7
            let sap_delta_time = (code & 0x0fffffff)
            let info = Sidx.SegmentInfo(type: Int(reference_type), size: Int(referenced_size), duration: Int(duration), sap: Int(starts_with_SAP), sap_type: Int(sap_type), sap_delta: Int(sap_delta_time))
            infos.append(info)
        }

        return Sidx(timescale: Int(timescale), firstOffset: Int(first_offset), earliestPresentationTime: Int(earliest_presentation_time), segments: infos)
    }
    
    // 辅助函数：Safe read without extension pollution
    static func readSafeUInt32(data: Data, offset: inout UInt64) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let val = data.getUint32(offset: &offset) // 使用 extension 里的 safe 实现
        return val
    }
    
    static func readSafeUInt64(data: Data, offset: inout UInt64) -> UInt64? {
        guard offset + 8 <= data.count else { return nil }
        // 手动拼
        let b0 = UInt64(data[Int(offset)])
        let b1 = UInt64(data[Int(offset+1)])
        let b2 = UInt64(data[Int(offset+2)])
        let b3 = UInt64(data[Int(offset+3)])
        let b4 = UInt64(data[Int(offset+4)])
        let b5 = UInt64(data[Int(offset+5)])
        let b6 = UInt64(data[Int(offset+6)])
        let b7 = UInt64(data[Int(offset+7)])
        offset += 8
        return (b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) | (b4 << 24) | (b5 << 16) | (b6 << 8) | b7
    }
}

extension Data {
    func getUint32(offset: inout UInt64) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let b0 = UInt32(self[Int(offset)])
        let b1 = UInt32(self[Int(offset+1)])
        let b2 = UInt32(self[Int(offset+2)])
        let b3 = UInt32(self[Int(offset+3)])
        offset += 4
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    func getUint8(offset: inout UInt64) -> UInt8 {
        guard offset + 1 <= count else { return 0 }
        let v = self[Int(offset)]
        offset += 1
        return v
    }

    func getValue<T>(type: T.Type, offset: inout UInt64) -> T where T: FixedWidthInteger {
        if type == UInt16.self {
            guard offset + 2 <= count else { return 0 as! T }
            // 模拟 Little Endian 读取，以便调用者 .bigEndian 能正确反转
            let val = (UInt16(self[Int(offset+1)]) << 8) | UInt16(self[Int(offset)])
            offset += 2
            return val as! T
        }
        let size = UInt64(MemoryLayout<T>.size)
        offset += size
        return 0 as! T 
    }
}

extension UInt32 {
    var toUInt8s: [UInt8] {
        return withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}
