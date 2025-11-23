import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
final class QRLoginViewModel: ObservableObject {
    enum LoginState: Equatable {
        case idle
        case generating
        case scanning(URL, String) // url, key
        case confirmed
        case expired
        case failed(String)
    }

    @Published var qrImage: Image?
    @Published var state: LoginState = .idle
    @Published var userProfile: UserProfile?

    private let context = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()
    private var pollTask: Task<Void, Never>?
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()

    private struct GenerateResponse: Decodable {
        struct Data: Decodable { let url: String; let qrcode_key: String }
        let code: Int
        let message: String
        let data: Data
    }

    struct UserProfile: Decodable, Equatable {
        let uname: String
        let face: URL
    }

    private struct PollResponse: Decodable {
        struct Data: Decodable { let code: Int; let message: String }
        let code: Int
        let message: String
        let data: Data
    }

    func startLogin() {
        pollTask?.cancel()
        state = .generating
        qrImage = nil

        Task {
            do {
                let generateURL = URL(string: "https://passport.bilibili.com/x/passport-login/web/qrcode/generate")!
                var request = URLRequest(url: generateURL)
                request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
                let (data, _) = try await session.data(for: request)
                let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
                guard decoded.code == 0 else {
                    throw URLError(.badServerResponse)
                }

                guard let link = URL(string: decoded.data.url) else {
                    throw URLError(.badURL)
                }

                qrImage = makeQRImage(from: decoded.data.url)
                state = .scanning(link, decoded.data.qrcode_key)
                beginPolling(key: decoded.data.qrcode_key)
            } catch {
                state = .failed("生成二维码失败：\(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        pollTask?.cancel()
        state = .idle
        qrImage = nil
    }

    private func beginPolling(key: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                    guard case .scanning = state else { return }
                    let pollURL = URL(string: "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=\(key)")!
                    var request = URLRequest(url: pollURL)
                    request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
                    let (data, _) = try await session.data(for: request)
                    let decoded = try JSONDecoder().decode(PollResponse.self, from: data)

                    // data.code: 0=成功, 86038=二维码失效, 86090=已扫码未确认, 86039=未扫码
                    switch decoded.data.code {
                    case 0:
                        state = .confirmed
                        await fetchUserProfile()
                        pollTask?.cancel()
                        return
                    case 86038:
                        state = .expired
                        pollTask?.cancel()
                        return
                    default:
                        continue
                    }
                } catch {
                    state = .failed("轮询失败：\(error.localizedDescription)")
                    pollTask?.cancel()
                    return
                }
            }
        }
    }

    private func makeQRImage(from string: String) -> Image? {
        let data = Data(string.utf8)
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let outputImage = qrFilter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1.0, orientation: .up)
    }

    private func fetchUserProfile() async {
        do {
            let navURL = URL(string: "https://api.bilibili.com/x/web-interface/nav")!
            var request = URLRequest(url: navURL)
            request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (VisionOS) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }

            struct NavResponse: Decodable {
                struct Data: Decodable {
                    let uname: String
                    let face: String
                }
                let data: Data
            }

            let decoded = try JSONDecoder().decode(NavResponse.self, from: data)
            if let url = URL(string: decoded.data.face) {
                userProfile = UserProfile(uname: decoded.data.uname, face: url)
            }
        } catch {
            // ignore errors for optional profile fetch
        }
    }
}
