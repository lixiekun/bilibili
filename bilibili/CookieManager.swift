import Foundation

enum CookieManager {
    private static let key = "savedCookies"

    static func save() {
        guard let cookies = HTTPCookieStorage.shared.cookies, !cookies.isEmpty else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: cookies, requiringSecureCoding: false)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Failed to save cookies: \(error)")
        }
    }

    @discardableResult
    static func restore() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: key) else { return false }
        do {
            if let cookies = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, HTTPCookie.self], from: data) as? [HTTPCookie] {
                cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
                return true
            }
        } catch {
            print("Failed to restore cookies: \(error)")
        }
        return false
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
