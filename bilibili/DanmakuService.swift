import Foundation
import Combine
import Compression

class DanmakuService {
    private let session = URLSession.shared
    
    enum DanmakuError: Error {
        case networkError(Error)
        case invalidData
        case decompressionFailed
        case parsingFailed
    }
    
    /// 获取指定 CID 的弹幕列表
    func fetchDanmaku(cid: Int) async throws -> [Danmaku] {
        let urlString = "https://api.bilibili.com/x/v1/dm/list.so?oid=\(cid)"
        guard let url = URL(string: urlString) else { throw DanmakuError.invalidData }
        
        var request = URLRequest(url: url)
        // 必须设置 User-Agent，否则可能返回 403 或空数据
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DanmakuError.networkError(URLError(.badServerResponse))
        }
        
        // 尝试解压数据
        var xmlData = data
        
        // 尝试 zlib 解压
        // 使用自定义扩展进行解压
        if let decompressed = data.decompressedData() {
            xmlData = decompressed
        } else {
            // 如果 zlib 失败，可能是 raw deflate 或根本没压缩
             let prefix = String(data: data.prefix(50), encoding: .utf8) ?? ""
             if !prefix.contains("<?xml") && !prefix.contains("<i") {
                 print("Warning: Data might be raw deflate or unknown format")
             }
        }
        
        return try parseXML(data: xmlData)
    }
    
    private func parseXML(data: Data) throws -> [Danmaku] {
        let parser = DanmakuXMLParser(data: data)
        return parser.parse()
    }
}

// MARK: - XML Parser
private class DanmakuXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var danmakus: [Danmaku] = []
    private var currentAttributes: String?
    private var currentContent: String = ""
    
    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }
    
    func parse() -> [Danmaku] {
        parser.parse()
        return danmakus.sorted { $0.time < $1.time }
    }
    
    // 遇到开始标签
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "d" {
            // <d p="...">...</d>
            // p 属性包含了弹幕的元数据
            currentAttributes = attributeDict["p"]
            currentContent = ""
        }
    }
    
    // 遇到文本内容
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentContent += string
    }
    
    // 遇到结束标签
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "d", let attrs = currentAttributes {
            if let danmaku = Danmaku(attributes: attrs, content: currentContent) {
                danmakus.append(danmaku)
            }
            currentAttributes = nil
            currentContent = ""
        }
    }
}

extension Data {
    /// 使用 Compression 框架进行 zlib 解压
    func decompressedData() -> Data? {
        // 增加 8MB 作为缓冲区大小限制，通常弹幕数据不会超过这个大小
        let bufferSize = 8 * 1024 * 1024
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }
        
        return self.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let sourcePointer = sourceBuffer.baseAddress?.bindMemory(to: UInt8.self, capacity: sourceBuffer.count) else { return nil }
            
            // zlib header 检测 (78 9C etc)
            // COMPRESSION_ZLIB 会处理 header
            
            let decodedSize = compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                sourcePointer,
                sourceBuffer.count,
                nil,
                COMPRESSION_ZLIB
            )
            
            if decodedSize > 0 {
                return Data(bytes: destinationBuffer, count: decodedSize)
            } 
            // COMPRESSION_ZLIB 通常能处理大部分 B 站弹幕数据
            // 如果失败，可能是不带 header 的 raw deflate，或者是未压缩数据
            
            return nil
        }
    }
}

